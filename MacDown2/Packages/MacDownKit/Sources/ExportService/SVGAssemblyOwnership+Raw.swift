import Foundation

extension SVGAssemblyOwnership {
    /// HTML parsing can foster SVG and its two comments out of an invalid
    /// container together. Compare the raw open-tag stack at each private
    /// marker with the browser-parsed ancestor chain before trusting location.
    static func rawAncestorMap(for markers: [String], in html: String) -> [String: [String]]? {
        let wanted = Set(markers)
        guard wanted.count == markers.count else { return nil }
        let scalars = Array(html.unicodeScalars)
        var found: [String: [String]] = [:]
        var stack: [String] = []
        var cursor = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else { cursor += 1; continue }
            if HTMLTagScanner.hasPrefix("<!--", at: cursor, in: scalars) {
                guard let end = HTMLTagScanner.commentEnd(from: cursor, in: scalars) else { return nil }
                let comment = String(String.UnicodeScalarView(scalars[cursor ..< end]))
                if wanted.contains(comment) {
                    guard found.updateValue(stack, forKey: comment) == nil else { return nil }
                }
                cursor = end
                continue
            }
            guard let end = consumeMarkup(at: cursor, scalars: scalars, stack: &stack)
            else { return nil }
            cursor = end
        }
        return stack.isEmpty && found.count == wanted.count ? found : nil
    }

    private static func consumeMarkup(
        at cursor: Int, scalars: [Unicode.Scalar], stack: inout [String]
    ) -> Int? {
        if HTMLTagScanner.hasPrefix("<!", at: cursor, in: scalars) {
            guard let end = scalars[cursor...].firstIndex(of: ">") else { return nil }
            return end + 1
        }
        guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
        if tag.isClosing {
            guard stack.last == tag.name else { return nil }
            stack.removeLast()
        } else if !tag.isSelfClosing, !voidTags.contains(tag.name) {
            if tag.name == "style" || tag.name == "script" {
                guard let end = HTMLTagScanner.skipPast("</\(tag.name)", from: tag.end, in: scalars)
                else { return nil }
                return end
            }
            stack.append(tag.name)
        }
        return tag.end
    }

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ]
}
