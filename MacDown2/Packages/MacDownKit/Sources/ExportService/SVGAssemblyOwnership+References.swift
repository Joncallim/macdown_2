import Foundation
import SwiftSoup

extension SVGAssemblyOwnership {
    static func referenceTargets(in elements: [Element], allowExternal: Bool = false) -> Set<String>? {
        var targets: Set<String> = []
        for element in elements {
            if element.tagNameNormal() == "style" {
                guard let urls = localURLs(in: element.data(), css: true, allowExternal: allowExternal)
                else { return nil }
                targets.formUnion(urls)
            }
            for attribute in element.getAttributes()?.asList() ?? [] {
                let name = attribute.getKey().lowercased()
                let value = attribute.getValue()
                if name == "href" || name == "xlink:href" {
                    if value.first == "#" {
                        targets.insert(String(value.dropFirst()))
                    }
                } else if ariaReferences.contains(name) {
                    targets.formUnion(value.split(whereSeparator: \.isWhitespace).map(String.init))
                } else if name == "style" || urlAttributes.contains(name) {
                    guard name != "style" || (!value.contains("\\") && !value.contains("&")),
                          let urls = localURLs(in: value, css: name == "style", allowExternal: allowExternal)
                    else { return nil }
                    targets.formUnion(urls)
                }
            }
        }
        return targets
    }

    /// CSS strings (notably `content:"url(#paint)"`) are text, while a
    /// function token outside a string is a resource edge. The source parser
    /// has already rejected CSS escapes in admitted SVGs; outside styles with
    /// escapes fail closed in the definition inventory.
    private static func localURLs(in text: String, css: Bool, allowExternal: Bool) -> Set<String>? {
        let scalars = Array(text.unicodeScalars)
        var targets: Set<String> = []
        var cursor = 0
        var quote: Unicode.Scalar?
        while cursor < scalars.count {
            if css, let current = quote {
                if scalars[cursor] == current {
                    quote = nil
                }
                cursor += 1
                continue
            }
            if css, scalars[cursor] == "\"" || scalars[cursor] == "'" {
                quote = scalars[cursor]
                cursor += 1
                continue
            }
            if cursor + 4 <= scalars.count,
               String(String.UnicodeScalarView(scalars[cursor ..< cursor + 4])).lowercased() == "url(" {
                guard let token = urlToken(in: scalars, afterOpen: cursor + 4, allowExternal: allowExternal)
                else { return nil }
                if let id = token.target {
                    targets.insert(id)
                }
                let end = token.end
                cursor = end + 1
                continue
            }
            cursor += 1
        }
        return quote == nil ? targets : nil
    }

    private static func urlToken(
        in scalars: [Unicode.Scalar], afterOpen: Int, allowExternal: Bool
    ) -> (end: Int, target: String?)? {
        guard let end = scalars[afterOpen...].firstIndex(of: ")") else { return nil }
        var value = String(String.UnicodeScalarView(scalars[afterOpen ..< end]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = value.first, first == "\"" || first == "'" {
            guard value.count >= 2, value.last == first else { return nil }
            value.removeFirst()
            value.removeLast()
        }
        if value.first == "#" {
            let id = String(value.dropFirst())
            guard SVGIDNamespace.validID(id) else { return nil }
            return (end, id)
        }
        guard allowExternal || value.lowercased().hasPrefix("data:") else { return nil }
        return (end, nil)
    }

    private static let urlAttributes: Set<String> = [
        "clip-path", "color-profile", "cursor", "fill", "filter", "marker", "marker-start",
        "marker-mid", "marker-end", "mask", "stroke",
    ]
    private static let ariaReferences: Set<String> = [
        "aria-labelledby", "aria-describedby", "aria-controls", "aria-owns", "aria-flowto", "aria-details",
    ]
}
