import Foundation

extension SVGIDNamespace {
    static func rewriteStyle(
        _ css: String, ids: Set<String>, prefix: String, scopeID: String, rootClasses: Set<String>
    ) -> String? {
        // The bundled D2 and Mermaid renderers emit quoted font values,
        // @font-face and @keyframes. Scan balanced blocks and quoted text so
        // braces in a string cannot turn declaration bytes into selectors.
        // Unknown at-rules, comments and CSS escapes remain fail-closed.
        guard !css.contains("/*"), !css.contains("\\"), !css.contains("&") else { return nil }
        var state = CSSState(rootClasses: rootClasses, knownFontFaces: [])
        for character in css {
            guard state.consume(character, ids: ids, prefix: prefix, scopeID: scopeID) else { return nil }
        }
        guard let first = state.finish() else { return nil }
        guard !state.declaredFontFaces.isEmpty else { return first }
        var final = CSSState(rootClasses: rootClasses, knownFontFaces: state.declaredFontFaces)
        for character in css {
            guard final.consume(character, ids: ids, prefix: prefix, scopeID: scopeID) else { return nil }
        }
        guard final.declaredFontFaces == state.declaredFontFaces else { return nil }
        return final.finish()
    }

    private enum CSSBlock {
        case group
        case keyframes
        case fontFace
        case declarations
    }

    private struct CSSState {
        let rootClasses: Set<String>
        let knownFontFaces: Set<String>
        var declaredKeyframes: Set<String> = []
        var declaredFontFaces: Set<String> = []
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
                guard stack.last != .declarations, stack.last != .fontFace,
                      let atRule = SVGIDNamespace.atRuleBlock(trimmed) else { return false }
                kind = atRule
                if atRule == .keyframes {
                    guard let name = SVGIDNamespace.keyframeName(
                        segment.trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                        declaredKeyframes.insert(name).inserted else { return false }
                    output += "@keyframes \(prefix)\(name)"
                } else {
                    output += segment
                }
            } else if stack.last == .keyframes {
                guard trimmed == "from" || trimmed == "to" || trimmed.hasSuffix("%"),
                      !trimmed.contains(";") else { return false }
                kind = .declarations
                output += segment
            } else {
                guard stack.last != .declarations, stack.last != .fontFace,
                      let selector = SVGIDNamespace.rewriteSelector(
                          segment, ids: ids, prefix: prefix, scopeID: scopeID, rootClasses: rootClasses
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
            if kind == .declarations || kind == .fontFace {
                if kind == .fontFace {
                    guard let name = SVGIDNamespace.fontFaceName(in: segment) else { return false }
                    declaredFontFaces.insert(name)
                }
                guard let rewritten = SVGIDNamespace.rewriteDeclarations(
                    segment, ids: ids, prefix: prefix, fontFaces: knownFontFaces
                )
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
        case "@font-face": return prelude == name ? .fontFace : nil
        case "@keyframes": return keyframeName(prelude) == nil ? nil : .keyframes
        case "@media", "@supports", "@container", "@layer": return .group
        default: return nil
        }
    }

    private static func rewriteDeclarations(
        _ declarations: String, ids: Set<String>, prefix: String, fontFaces: Set<String>
    ) -> String? {
        var scanner = DeclarationScanner()
        for character in declarations {
            guard scanner.consume(character, ids: ids, prefix: prefix, fontFaces: fontFaces) else { return nil }
        }
        return scanner.finish(ids: ids, prefix: prefix, fontFaces: fontFaces)
    }

    private struct DeclarationScanner {
        var output = ""
        var segment = ""
        var quote: Character?
        var parentheses = 0

        mutating func consume(
            _ character: Character, ids: Set<String>, prefix: String, fontFaces: Set<String>
        ) -> Bool {
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
                guard let rewritten = rewriteDeclaration(
                    segment, ids: ids, prefix: prefix, fontFaces: fontFaces
                ) else { return false }
                output += rewritten + ";"
                segment = ""
            default: segment.append(character)
            }
            return true
        }

        func finish(ids: Set<String>, prefix: String, fontFaces: Set<String>) -> String? {
            guard quote == nil, parentheses == 0,
                  let rewritten = rewriteDeclaration(segment, ids: ids, prefix: prefix, fontFaces: fontFaces)
            else { return nil }
            return output + rewritten
        }
    }

    private static func rewriteDeclaration(
        _ declaration: String, ids _: Set<String>, prefix: String, fontFaces: Set<String>
    ) -> String? {
        guard safeResourceURLs(in: declaration) else { return nil }
        // A quoted content string is text, while content:url(#id) is a
        // resource. Scan actual CSS function tokens outside string literals.
        let rewritten = rewriteCSSTokenURLs(declaration, prefix: prefix)
        guard let animation = rewriteAnimation(in: rewritten, prefix: prefix) else { return nil }
        return rewriteFontFamily(in: animation, names: fontFaces, prefix: prefix)
    }

    static func rewriteInlineStyle(_ declarations: String, ids: Set<String>, prefix: String) -> String? {
        guard !declarations.contains("&"), !declarations.contains("\\"), !declarations.contains("/*")
        else { return nil }
        return rewriteDeclarations(declarations, ids: ids, prefix: prefix, fontFaces: [])
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
}
