import Foundation

extension SVGIDNamespace {
    static func rewriteStyle(_ css: String, ids: Set<String>, prefix: String, scopeID: String) -> String? {
        // The bundled D2 and Mermaid renderers emit quoted font values,
        // @font-face and @keyframes. Scan balanced blocks and quoted text so
        // braces in a string cannot turn declaration bytes into selectors.
        // Unknown at-rules, comments and CSS escapes remain fail-closed.
        guard !css.contains("/*"), !css.contains("\\"), !css.contains("&") else { return nil }
        var state = CSSState()
        for character in css {
            guard state.consume(character, ids: ids, prefix: prefix, scopeID: scopeID) else { return nil }
        }
        return state.finish()
    }

    private enum CSSBlock {
        case group
        case keyframes
        case declarations
    }

    private struct CSSState {
        var output = ""
        var segment = ""
        var stack: [CSSBlock] = []
        var quote: Character?

        mutating func consume(
            _ character: Character, ids: Set<String>, prefix: String, scopeID: String
        ) -> Bool {
            if let quote {
                segment.append(character)
                if character == quote {
                    self.quote = nil
                }
                return true
            }
            if character == "\"" || character == "'" {
                quote = character
                segment.append(character)
                return true
            }
            switch character {
            case "{": return open(ids: ids, prefix: prefix, scopeID: scopeID)
            case "}": return close(ids: ids, prefix: prefix)
            default:
                segment.append(character)
                return true
            }
        }

        mutating func open(ids: Set<String>, prefix: String, scopeID: String) -> Bool {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind: CSSBlock
            if trimmed.hasPrefix("@") {
                guard stack.last != .declarations,
                      let atRule = SVGIDNamespace.atRuleBlock(trimmed) else { return false }
                kind = atRule
                output += segment
            } else if stack.last == .keyframes {
                guard trimmed == "from" || trimmed == "to" || trimmed.hasSuffix("%"),
                      !trimmed.contains(";") else { return false }
                kind = .declarations
                output += segment
            } else {
                guard stack.last != .declarations,
                      let selector = SVGIDNamespace.rewriteSelector(
                          segment, ids: ids, prefix: prefix, scopeID: scopeID
                      )
                else { return false }
                kind = .declarations
                output += selector
            }
            output += "{"
            stack.append(kind)
            segment = ""
            return true
        }

        mutating func close(ids: Set<String>, prefix: String) -> Bool {
            guard let kind = stack.popLast() else { return false }
            if kind == .declarations {
                guard let rewritten = SVGIDNamespace.rewriteDeclarations(segment, ids: ids, prefix: prefix)
                else { return false }
                output += rewritten
            } else {
                guard segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                output += segment
            }
            output += "}"
            segment = ""
            return true
        }

        func finish() -> String? {
            guard quote == nil, stack.isEmpty,
                  !segment.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
            else { return nil }
            return output + segment
        }
    }

    private static func atRuleBlock(_ prelude: String) -> CSSBlock? {
        // One complete at-rule may precede a block. A semicolon or second @
        // could hide a resource-loading statement before an accepted rule.
        guard prelude.first == "@", !prelude.contains(";"), !prelude.dropFirst().contains("@") else { return nil }
        let name = String(prelude.prefix { !$0.isWhitespace && $0 != "(" })
        switch name {
        case "@font-face": return prelude == name ? .declarations : nil
        case "@keyframes": return prelude.count > name.count ? .keyframes : nil
        case "@media", "@supports", "@container", "@layer": return .group
        default: return nil
        }
    }

    private static func rewriteDeclarations(_ declarations: String, ids: Set<String>, prefix: String) -> String? {
        var scanner = DeclarationScanner()
        for character in declarations {
            guard scanner.consume(character, ids: ids, prefix: prefix) else { return nil }
        }
        return scanner.finish(ids: ids, prefix: prefix)
    }

    private struct DeclarationScanner {
        var output = ""
        var segment = ""
        var quote: Character?
        var parentheses = 0

        mutating func consume(_ character: Character, ids: Set<String>, prefix: String) -> Bool {
            if let current = quote {
                segment.append(character)
                if character == current {
                    quote = nil
                }
                return true
            }
            switch character {
            case "\"", "'": quote = character; segment.append(character)
            case "(": parentheses += 1; segment.append(character)
            case ")":
                guard parentheses > 0 else { return false }
                parentheses -= 1
                segment.append(character)
            case ";" where parentheses == 0:
                guard let rewritten = rewriteDeclaration(segment, ids: ids, prefix: prefix) else { return false }
                output += rewritten + ";"
                segment = ""
            default: segment.append(character)
            }
            return true
        }

        func finish(ids: Set<String>, prefix: String) -> String? {
            guard quote == nil, parentheses == 0,
                  let rewritten = rewriteDeclaration(segment, ids: ids, prefix: prefix)
            else { return nil }
            return output + rewritten
        }
    }

    private static func rewriteDeclaration(_ declaration: String, ids _: Set<String>, prefix: String) -> String? {
        guard safeResourceURLs(in: declaration) else { return nil }
        // A quoted content string is text, while content:url(#id) is a
        // resource. Scan actual CSS function tokens outside string literals.
        return rewriteCSSTokenURLs(declaration, prefix: prefix)
    }

    static func rewriteInlineStyle(_ declarations: String, ids: Set<String>, prefix: String) -> String? {
        guard !declarations.contains("&"), !declarations.contains("\\"), !declarations.contains("/*")
        else { return nil }
        return rewriteDeclarations(declarations, ids: ids, prefix: prefix)
    }

    private static func rewriteCSSTokenURLs(_ declaration: String, prefix: String) -> String {
        let scalars = Array(declaration.unicodeScalars)
        var output = ""
        var cursor = 0
        var quote: Unicode.Scalar?
        while cursor < scalars.count {
            if let current = quote {
                output.unicodeScalars.append(scalars[cursor])
                if scalars[cursor] == current {
                    quote = nil
                }
                cursor += 1
                continue
            }
            if scalars[cursor] == "\"" || scalars[cursor] == "'" {
                quote = scalars[cursor]
                output.unicodeScalars.append(scalars[cursor])
                cursor += 1
                continue
            }
            if cursor + 4 <= scalars.count,
               String(String.UnicodeScalarView(scalars[cursor ..< (cursor + 4)])).lowercased() == "url(" {
                guard let end = scalars[(cursor + 4)...].firstIndex(of: ")") else { return declaration }
                let token = String(String.UnicodeScalarView(scalars[cursor ... end]))
                output += rewriteURLReferences(token, ids: [], prefix: prefix)
                cursor = end + 1
                continue
            }
            output.unicodeScalars.append(scalars[cursor])
            cursor += 1
        }
        return output
    }

    static func safeResourceURLs(in declaration: String) -> Bool {
        // The bundled D2 font is a data URL. Other CSS resources could fetch
        // over the network or from disk, so the opt-in path keeps only SVG
        // fragments and embedded font bytes.
        // Inline presentation/style attributes do not pass rewriteStyle's
        // CSS escape/comment gate, so enforce it here too before URL scanning.
        guard !declaration.contains("\\"), !declaration.contains("/*"), !declaration.contains("&")
        else { return false }
        let lower = declaration.lowercased()
        guard !["image-set(", "image(", "cross-fade("].contains(where: lower.contains) else { return false }
        var cursor = lower.startIndex
        while let token = lower.range(of: "url(", range: cursor ..< lower.endIndex) {
            guard let close = lower[token.upperBound...].firstIndex(of: ")") else { return false }
            var value = lower[token.upperBound ..< close].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'" {
                guard value.last == first else { return false }
                value.removeFirst()
                value.removeLast()
            }
            let embeddedFont = ["data:application/font-woff;base64,", "data:font/woff;base64,"]
                .contains { prefix in
                    value.hasPrefix(prefix) && !value.dropFirst(prefix.count).isEmpty
                        && value.dropFirst(prefix.count).allSatisfy(base64Characters.contains)
                }
            guard (value.first == "#" && validID(String(value.dropFirst()))) || embeddedFont else { return false }
            cursor = lower.index(after: close)
        }
        return true
    }

    private static let base64Characters = Set("abcdefghijklmnopqrstuvwxyz0123456789+/=")

    private static func rewriteSelector(
        _ selector: String, ids: Set<String>, prefix: String, scopeID: String
    ) -> String? {
        let components = splitSelectors(selector)
        guard !components.isEmpty else { return nil }
        var rewritten: [String] = []
        for component in components {
            guard let value = rewriteSelectorComponent(
                component, ids: ids, prefix: prefix, scopeID: scopeID
            ) else { return nil }
            rewritten.append(value)
        }
        return rewritten.joined(separator: ",")
    }

    private static func splitSelectors(_ selector: String) -> [String] {
        var scanner = SelectorSplitter()
        for character in selector {
            scanner.consume(character)
        }
        return scanner.finish()
    }

    private struct SelectorSplitter {
        var parts: [String] = []
        var segment = ""
        var quote: Character?
        var nesting = 0

        mutating func consume(_ character: Character) {
            if let current = quote {
                segment.append(character)
                if character == current {
                    quote = nil
                }
                return
            }
            if character == "\"" || character == "'" {
                quote = character
                segment.append(character)
                return
            }
            if character == ",", nesting == 0 {
                parts.append(segment)
                segment = ""
                return
            }
            nesting += nestingChange(character)
            segment.append(character)
        }

        private func nestingChange(_ character: Character) -> Int {
            switch character {
            case "[", "(": 1
            case "]", ")": -1
            default: 0
            }
        }

        func finish() -> [String] {
            guard quote == nil, nesting == 0 else { return [] }
            return parts + [segment]
        }
    }

    private static func rewriteSelectorComponent(
        _ selector: String, ids _: Set<String>, prefix: String, scopeID: String
    ) -> String? {
        // Mermaid uses selectors such as `#diagram [id$="-arrowhead"]`.
        // Rewrite the bare ID selector, preserving the quoted suffix. A
        // fragment inside quotes needs attribute-selector parsing and fails
        // closed rather than rewriting arbitrary string content.
        guard admittedIDAttributeSelectors(in: selector),
              let output = rewriteSelectorIDs(selector, prefix: prefix) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") {
            return output
        }
        return "#\(scopeID) " + output
    }

    private static func rewriteSelectorIDs(_ selector: String, prefix: String) -> String? {
        let scalars = Array(selector.unicodeScalars)
        var output = ""
        var cursor = 0
        var quote: Unicode.Scalar?
        while cursor < scalars.count {
            if let current = quote {
                guard scalars[cursor] != "#" else { return nil }
                output.unicodeScalars.append(scalars[cursor])
                if scalars[cursor] == current {
                    quote = nil
                }
                cursor += 1
                continue
            }
            if scalars[cursor] == "\"" || scalars[cursor] == "'" {
                quote = scalars[cursor]
                output.unicodeScalars.append(scalars[cursor])
                cursor += 1
                continue
            }
            guard scalars[cursor] == "#" else {
                output.unicodeScalars.append(scalars[cursor])
                cursor += 1
                continue
            }
            let start = cursor + 1
            var end = start
            while end < scalars.count, validID(String(scalars[end])) {
                end += 1
            }
            guard end > start else { return nil }
            let id = String(String.UnicodeScalarView(scalars[start ..< end]))
            output += "#\(prefix)\(id)"
            cursor = end
        }
        return quote == nil ? output : nil
    }

    private static func admittedIDAttributeSelectors(in selector: String) -> Bool {
        let source = selector as NSString
        let matches = idAttributeSelector.matches(in: selector, range: NSRange(location: 0, length: source.length))
        return matches.allSatisfy { match in
            let operatorRange = match.range(at: 1)
            return operatorRange.location != NSNotFound && source.substring(with: operatorRange) == "$="
        }
    }

    private static let idAttributeSelector: NSRegularExpression = {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\[\s*id(?![a-z0-9_-])\s*([~|^$*]?=)?"#
        ) else { preconditionFailure("invalid SVG ID attribute selector pattern") }
        return expression
    }()
}
