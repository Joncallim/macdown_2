import Foundation

/// Removes active content from HTML fragments contributed by renderers before they are
/// spliced into an export.
///
/// Diagram renderers (Graphviz, D2, Mermaid) turn author-controlled text into SVG, and a
/// diagram link such as `URL="javascript:…"` survives as `xlink:href`/`href`. Contributed
/// HTML bypasses `ExportURLPolicy`, which only sees authored Markdown links, so this applies
/// the same scheme rules plus the usual script/handler/embed removal. Typeset math images
/// (`data:image/png;base64,…` in `src`) are unaffected.
enum DerivedHTMLSanitizer {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals in this file; a failure here is a programming error.
        guard let compiled = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { preconditionFailure("invalid sanitizer pattern \(pattern)") }
        return compiled
    }

    private static let elementBlocks = regex(#"<(script|iframe|object|embed)\b[^>]*>.*?</\1\s*>"#)
    private static let strayElements = regex(#"</?(script|iframe|object|embed)\b[^>]*>"#)
    private static let handlers = regex(#"(?<=[\s"'/])on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#)
    private static let urlAttributes = regex(
        #"(?<=[\s"'/])((?:xlink:)?href|src|action|formaction)(\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
    )

    static func sanitized(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var result = replacing(elementBlocks, in: html) { _ in "" }
        result = replacing(strayElements, in: result) { _ in "" }
        result = replacing(handlers, in: result) { _ in "" }
        return replacing(urlAttributes, in: result) { match in
            let value = [3, 4, 5].lazy.compactMap { match.group($0) }.first ?? ""
            let name = match.group(1) ?? ""
            return isSafe(decodingEntities(in: value), attribute: name)
                ? match.whole
                : "\(name)\(match.group(2) ?? "=")\"#\""
        }
    }

    private static let embeddedImage = regex(#"^\s*data:image/(png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=\s]*$"#)

    private static func isSafe(_ url: String, attribute: String) -> Bool {
        if attribute.lowercased() == "src",
           embeddedImage.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) != nil {
            return true
        }
        return ExportURLPolicy.isSafe(url)
    }

    private struct Match {
        let whole: String
        private let result: NSTextCheckingResult
        private let source: NSString

        init(_ result: NSTextCheckingResult, in source: NSString) {
            self.result = result
            self.source = source
            whole = source.substring(with: result.range)
        }

        func group(_ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }
    }

    private static func replacing(
        _ expression: NSRegularExpression,
        in text: String,
        with transform: (Match) -> String
    ) -> String {
        let source = text as NSString
        var output = ""
        var cursor = 0
        for result in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: result.range.location - cursor))
            output += transform(Match(result, in: source))
            cursor = result.range.location + result.range.length
        }
        return output + source.substring(from: cursor)
    }

    private static let namedEntities = [
        "&colon;": ":", "&Tab;": "\t", "&NewLine;": "\n", "&amp;": "&", "&lpar;": "(", "&rpar;": ")",
    ]
    private static let numericEntity = regex(#"&#(x[0-9a-f]+|[0-9]+);?"#)

    /// What a browser would read after resolving character references in an attribute.
    private static func decodingEntities(in value: String) -> String {
        guard value.contains("&") else { return value }
        var decoded = replacing(numericEntity, in: value) { match in
            let digits = match.group(1) ?? ""
            let code = digits.lowercased().hasPrefix("x")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? match.whole
        }
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }
}
