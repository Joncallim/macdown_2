import Foundation
import SwiftSoup

/// Gives each accepted diagram occurrence its own SVG IDs. Renderer caches keep
/// their canonical artwork; this runs only on the sanitized export fragment.
/// Unsupported SVG/CSS syntax fails closed so a partial rewrite cannot leave
/// references pointing at a different diagram or an authored element.
enum SVGIDNamespace {
    static func rewrite(_ html: String, occurrence: Int) -> String? {
        guard html.lowercased().contains("<svg") else { return html }
        let scalars = Array(html.unicodeScalars)
        guard let roots = findRoots(in: scalars), !roots.isEmpty else { return nil }
        var output = ""
        var copiedThrough = 0
        for (ordinal, root) in roots.enumerated() {
            output += String(String.UnicodeScalarView(scalars[copiedThrough ..< root.lowerBound]))
            let fragment = String(String.UnicodeScalarView(scalars[root]))
            guard let rewritten = rewriteRoot(fragment, prefix: "mt117-svg-\(occurrence)-\(ordinal)-")
            else { return nil }
            output += rewritten
            copiedThrough = root.upperBound
        }
        output += String(String.UnicodeScalarView(scalars[copiedThrough...]))
        return output
    }

    private static func findRoots(in scalars: [Unicode.Scalar]) -> [Range<Int>]? {
        var roots: [Range<Int>] = []
        var cursor = 0
        var rootStart: Int?
        var depth = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else { cursor += 1; continue }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if tag.name == "svg" {
                if !tag.isClosing {
                    guard !tag.isSelfClosing else { return nil }
                    if depth == 0 {
                        rootStart = cursor
                    }
                    depth += 1
                } else {
                    guard depth > 0 else { return nil }
                    depth -= 1
                    if depth == 0 {
                        guard let start = rootStart else { return nil }
                        roots.append(start ..< tag.end)
                        rootStart = nil
                    }
                }
            }
            cursor = tag.end
        }
        return depth == 0 ? roots : nil
    }

    private static func rewriteRoot(_ svg: String, prefix: String) -> String? {
        let scalars = Array(svg.unicodeScalars)
        guard let ids = collectIDs(in: scalars) else { return nil }
        guard !ids.isEmpty else { return svg }
        return rewriteTags(in: scalars, ids: ids, prefix: prefix)
    }

    private static func collectIDs(in scalars: [Unicode.Scalar]) -> Set<String>? {
        var ids: Set<String> = []
        var cursor = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else { cursor += 1; continue }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if !tag.isClosing {
                for attribute in tag.attributes where attribute.name == "id" {
                    guard let raw = attribute.value, let value = try? Parser.unescapeEntities(raw, true),
                          validID(value), ids.insert(value).inserted else { return nil }
                }
            }
            cursor = tag.end
        }
        return ids
    }

    private static func rewriteTags(in scalars: [Unicode.Scalar], ids: Set<String>, prefix: String) -> String? {
        var output = ""
        var cursor = 0
        var style = false
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else {
                let start = cursor
                while cursor < scalars.count, scalars[cursor] != "<" {
                    cursor += 1
                }
                let text = String(String.UnicodeScalarView(scalars[start ..< cursor]))
                if style {
                    guard let rewritten = rewriteStyle(text, ids: ids, prefix: prefix) else { return nil }
                    output += rewritten
                } else {
                    output += text
                }
                continue
            }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if tag.name == "style" {
                style = !tag.isClosing
            }
            if tag.isClosing {
                output += "</\(tag.name)>"
            } else {
                guard let opening = openingTag(tag, ids: ids, prefix: prefix) else { return nil }
                output += opening
            }
            cursor = tag.end
        }
        return style ? nil : output
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39)
                || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x61 && $0.value <= 0x7A)
                || $0 == "-" || $0 == "_"
        }
    }

    private static func openingTag(_ tag: HTMLTagScanner.Tag, ids: Set<String>, prefix: String) -> String? {
        var output = "<\(tag.name)"
        for attribute in tag.attributes {
            guard let raw = attribute.value else {
                output += " \(attribute.name)"
                continue
            }
            guard let value = try? Parser.unescapeEntities(raw, true) else { return nil }
            var updated = value
            switch attribute.name {
            case "id": updated = prefix + value
            case "href", "xlink:href":
                if value.first == "#", ids.contains(String(value.dropFirst())) {
                    updated = "#" + prefix + value.dropFirst()
                }
            case "aria-labelledby", "aria-describedby", "aria-controls", "aria-owns", "aria-flowto", "aria-details":
                updated = value.split(whereSeparator: \.isWhitespace).map {
                    ids.contains(String($0)) ? prefix + $0 : String($0)
                }.joined(separator: " ")
            default: break
            }
            if urlBearingAttributes.contains(attribute.name) {
                updated = rewriteURLReferences(updated, ids: ids, prefix: prefix)
            }
            let emitted = updated == value ? raw : HTMLEscaping.escape(updated)
            output += " \(attribute.name)=\"\(emitted)\""
        }
        return output + (tag.isSelfClosing ? " />" : ">")
    }

    private static func rewriteURLReferences(_ text: String, ids: Set<String>, prefix: String) -> String {
        guard text.range(of: "url(", options: .caseInsensitive) != nil else { return text }
        let source = text as NSString
        var output = text
        let matches = urlReference.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let idRange = match.range(at: 1)
            let id = source.substring(with: idRange)
            guard ids.contains(id) else { continue }
            output = (output as NSString).replacingCharacters(in: idRange, with: prefix + id)
        }
        return output
    }

    private static let urlReference: NSRegularExpression = {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)url\(\s*(?:&quot;|&apos;|["'])?\s*#([A-Za-z0-9_-]+)\s*(?:&quot;|&apos;|["'])?\s*\)"#
        ) else { preconditionFailure("invalid SVG URL reference pattern") }
        return expression
    }()

    private static let urlBearingAttributes: Set<String> = [
        "clip-path", "color-profile", "cursor", "fill", "filter", "marker", "marker-start",
        "marker-mid", "marker-end", "mask", "stroke", "style",
    ]

    private static func rewriteStyle(_ css: String, ids: Set<String>, prefix: String) -> String? {
        // Generated diagram CSS uses ordinary selector/declaration blocks.
        // Escapes, comments, quoted strings and at-rules require a full CSS
        // parser; reject them rather than rewriting a color or text literal.
        guard !css.contains("\\"), !css.contains("/*"), !css.contains("\""),
              !css.contains("'"), !css.contains("@") else { return nil }
        var output = ""
        var part = ""
        var inDeclarations = false
        for character in css {
            switch character {
            case "{":
                guard !inDeclarations else { return nil }
                output += rewriteSelector(part, ids: ids, prefix: prefix) + "{"
                part = ""
                inDeclarations = true
            case "}":
                guard inDeclarations else { return nil }
                output += rewriteURLReferences(part, ids: ids, prefix: prefix) + "}"
                part = ""
                inDeclarations = false
            default: part.append(character)
            }
        }
        guard !inDeclarations else { return nil }
        return output + part
    }

    private static func rewriteSelector(_ selector: String, ids: Set<String>, prefix: String) -> String {
        let scalars = Array(selector.unicodeScalars)
        var output = ""
        var cursor = 0
        while cursor < scalars.count {
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
        return output
    }
}
