import Foundation

extension SVGIDNamespace {
    static func admittedFontFaceScope(in scalars: [Unicode.Scalar]) -> Bool? {
        let hasFontFace = String(String.UnicodeScalarView(scalars)).lowercased().contains("@font-face")
        guard hasFontFace else { return false }
        var scanner = FontStyleScopeScanner()
        var cursor = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else {
                let start = cursor
                while cursor < scalars.count, scalars[cursor] != "<" {
                    cursor += 1
                }
                scanner.consumeText(String(String.UnicodeScalarView(scalars[start ..< cursor])))
                continue
            }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars), scanner.consumeTag(tag)
            else { return nil }
            cursor = tag.end
        }
        return scanner.finish()
    }

    private struct FontStyleScopeScanner {
        var inStyle = false
        var styleText = ""
        var foundFaceStyle = false

        mutating func consumeText(_ text: String) {
            if inStyle {
                styleText += text
            }
        }

        mutating func consumeTag(_ tag: HTMLTagScanner.Tag) -> Bool {
            guard tag.name == "style" else { return true }
            if !tag.isClosing {
                guard !inStyle else { return false }
                inStyle = true
                return true
            }
            guard inStyle else { return false }
            let compact = styleText.lowercased().filter { !$0.isWhitespace }
            let ownsFace = compact.contains("@font-face")
            guard ownsFace || (!compact.contains("font-family:") && !compact.contains("font:"))
            else { return false }
            foundFaceStyle = foundFaceStyle || ownsFace
            inStyle = false
            styleText = ""
            return true
        }

        func finish() -> Bool? {
            !inStyle && foundFaceStyle ? true : nil
        }
    }

    static func fontFaceName(in declarations: String) -> String? {
        guard let segments = fontDeclarationSegments(declarations) else { return nil }
        var name: String?
        var hasEmbeddedSource = false
        for segment in segments where !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let colon = segment.firstIndex(of: ":") else { return nil }
            let property = segment[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = segment[segment.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            switch property {
            case "font-family":
                guard name == nil, let family = fontName(value) else { return nil }
                name = family
            case "src":
                let lower = value.lowercased()
                guard !hasEmbeddedSource, lower.hasPrefix("url("),
                      lower.filter({ $0 == "(" }).count == 1,
                      lower.contains("data:application/font-woff;base64,")
                      || lower.contains("data:font/woff;base64,"),
                      safeResourceURLs(in: value) else { return nil }
                hasEmbeddedSource = true
            default: break
            }
        }
        return hasEmbeddedSource ? name : nil
    }

    static func rewriteFontFamily(in declaration: String, names: Set<String>, prefix: String) -> String? {
        guard !names.isEmpty, let colon = declaration.firstIndex(of: ":") else { return declaration }
        let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if property == "font" {
            return nil
        }
        guard property == "font-family" else { return declaration }
        let value = String(declaration[declaration.index(after: colon)...])
        guard !value.lowercased().contains("var(") else { return nil }
        let importance = value.firstIndex(of: "!")
        let body = importance.map { String(value[..<$0]) } ?? value
        let suffix = importance.map { String(value[$0...]) } ?? ""
        guard suffix.isEmpty || suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "!important"
        else { return nil }
        var rewritten: [String] = []
        for part in body.split(separator: ",", omittingEmptySubsequences: false) {
            let original = String(part)
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let name = fontName(trimmed), names.contains(name.lowercased()),
                  let range = original.range(of: name) else { return nil }
            var updated = original
            updated.replaceSubrange(range, with: prefix + name.lowercased())
            rewritten.append(updated)
        }
        return String(declaration[...colon]) + rewritten.joined(separator: ",") + suffix
    }

    private static func fontName(_ value: String) -> String? {
        var name = value
        if let first = name.first, first == "\"" || first == "'" {
            guard name.count >= 2, name.last == first else { return nil }
            name.removeFirst()
            name.removeLast()
        }
        return validID(name) ? name : nil
    }

    private static func fontDeclarationSegments(_ declarations: String) -> [String]? {
        var parts: [String] = []
        var segment = ""
        var quote: Character?
        var parentheses = 0
        for character in declarations {
            if let current = quote {
                segment.append(character)
                if character == current {
                    quote = nil
                }
                continue
            }
            switch character {
            case "\"", "'": quote = character; segment.append(character)
            case "(": parentheses += 1; segment.append(character)
            case ")":
                guard parentheses > 0 else { return nil }
                parentheses -= 1
                segment.append(character)
            case ";" where parentheses == 0:
                parts.append(segment)
                segment = ""
            default: segment.append(character)
            }
        }
        guard quote == nil, parentheses == 0 else { return nil }
        return parts + [segment]
    }
}
