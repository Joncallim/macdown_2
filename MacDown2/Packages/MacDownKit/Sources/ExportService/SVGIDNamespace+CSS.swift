import Foundation

extension SVGIDNamespace {
    static func rewriteStyle(_ css: String, ids: Set<String>, prefix: String) -> String? {
        // The bundled D2 and Mermaid renderers emit quoted font values,
        // @font-face and @keyframes. Scan balanced blocks and quoted text so
        // braces in a string cannot turn declaration bytes into selectors.
        // Unknown at-rules, comments and CSS escapes remain fail-closed.
        guard !css.contains("/*"), !css.contains("\\") else { return nil }
        var state = CSSState()
        for character in css {
            guard state.consume(character, ids: ids, prefix: prefix) else { return nil }
        }
        return state.finish()
    }

    private enum CSSBlock {
        case group
        case declarations
    }

    private struct CSSState {
        var output = ""
        var segment = ""
        var stack: [CSSBlock] = []
        var quote: Character?

        mutating func consume(_ character: Character, ids: Set<String>, prefix: String) -> Bool {
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
            case "{": return open(ids: ids, prefix: prefix)
            case "}": return close(ids: ids, prefix: prefix)
            default:
                segment.append(character)
                return true
            }
        }

        mutating func open(ids: Set<String>, prefix: String) -> Bool {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind: CSSBlock
            if trimmed.hasPrefix("@") {
                guard stack.last != .declarations else { return false }
                if trimmed.hasPrefix("@font-face") {
                    kind = .declarations
                } else if ["@keyframes", "@media", "@supports", "@container", "@layer"].contains(where: {
                    trimmed.hasPrefix($0)
                }) {
                    kind = .group
                } else {
                    return false
                }
                output += segment
            } else {
                guard stack.last != .declarations,
                      let selector = SVGIDNamespace.rewriteSelector(segment, ids: ids, prefix: prefix)
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

    private static func rewriteDeclaration(_ declaration: String, ids: Set<String>, prefix: String) -> String? {
        let property = declaration.split(separator: ":", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard safeResourceURLs(in: declaration) else { return nil }
        // CSS content strings are text, not references to rewrite. A real
        // content:url(...) still passed the resource admission check above.
        if property == "content" {
            return declaration
        }
        return rewriteURLReferences(declaration, ids: ids, prefix: prefix)
    }

    static func safeResourceURLs(in declaration: String) -> Bool {
        // The bundled D2 font is a data URL. Other CSS resources could fetch
        // over the network or from disk, so the opt-in path keeps only SVG
        // fragments and embedded font bytes.
        let lower = declaration.lowercased()
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

    private static func rewriteSelector(_ selector: String, ids: Set<String>, prefix: String) -> String? {
        // Mermaid uses selectors such as `#diagram [id$="-arrowhead"]`.
        // Rewrite the bare ID selector, preserving the quoted suffix. A
        // fragment inside quotes needs attribute-selector parsing and fails
        // closed rather than rewriting arbitrary string content.
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
            let id = String(String.UnicodeScalarView(scalars[start ..< end]))
            output += ids.contains(id) ? "#\(prefix)\(id)" : "#\(id)"
            cursor = end
        }
        return quote == nil ? output : nil
    }
}
