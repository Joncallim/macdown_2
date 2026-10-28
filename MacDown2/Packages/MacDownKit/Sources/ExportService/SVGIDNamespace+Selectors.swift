import Foundation

extension SVGIDNamespace {
    static func rewriteSelector(
        _ selector: String, ids: Set<String>, prefix: String, scopeID: String, rootClasses: Set<String>
    ) -> String? {
        let components = splitSelectors(selector)
        guard !components.isEmpty else { return nil }
        var rewritten: [String] = []
        for component in components {
            guard let value = rewriteSelectorComponent(
                component, ids: ids, prefix: prefix, scopeID: scopeID, rootClasses: rootClasses
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
        var unsupportedCombinator = false

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
            if character == "+" || character == "~" {
                unsupportedCombinator = true
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
            guard quote == nil, nesting == 0, !unsupportedCombinator else { return [] }
            return parts + [segment]
        }
    }

    private static func rewriteSelectorComponent(
        _ selector: String, ids: Set<String>, prefix: String, scopeID: String,
        rootClasses: Set<String>
    ) -> String? {
        // Mermaid uses selectors such as `#diagram [id$="-arrowhead"]`.
        // Rewrite the bare ID selector, preserving the quoted suffix. A
        // fragment inside quotes needs attribute-selector parsing and fails
        // closed rather than rewriting arbitrary string content.
        guard !canTargetRootWithoutAnID(selector, rootClasses: rootClasses) else { return nil }
        guard admittedIDAttributeSelectors(in: selector),
              let output = rewriteSelectorIDs(selector, ids: ids, prefix: prefix) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") {
            return output
        }
        return "#\(scopeID) " + output
    }

    private static func canTargetRootWithoutAnID(_ selector: String, rootClasses: Set<String>) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("svg"),
           trimmed.dropFirst(3).first.map({ !validID(String($0)) }) ?? true {
            return true
        }
        if trimmed.hasPrefix("*") || trimmed.hasPrefix("[") || trimmed.hasPrefix(":") {
            return true
        }
        guard trimmed.hasPrefix(".") else { return false }
        let firstClass = trimmed.dropFirst().prefix { validID(String($0)) }
        return rootClasses.contains(String(firstClass))
    }

    private static func rewriteSelectorIDs(_ selector: String, ids: Set<String>, prefix: String) -> String? {
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
            guard ids.contains(id) else { return nil }
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
