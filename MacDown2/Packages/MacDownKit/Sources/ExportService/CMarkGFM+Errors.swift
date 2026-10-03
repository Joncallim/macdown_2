import Foundation

extension CMarkGFM {
    enum CMarkError: Error, LocalizedError, CustomStringConvertible {
        case parserCreationFailed
        case parseProducedNoDocument
        case renderFailed

        var description: String {
            switch self {
            case .parserCreationFailed: "cmark could not create a parser"
            case .parseProducedNoDocument: "cmark produced no document"
            case .renderFailed: "cmark could not render HTML"
            }
        }

        var errorDescription: String? {
            description
        }
    }

    /// Replaces each deferred inline sentinel in the rendered HTML in ONE pass (a `replacingOccurrences` per
    /// contribution over the whole document was quadratic: 1000 table cells took 13 s).
    static func substitutingDeferredSentinels(_ specs: [CustomNodeSpec], in html: String) -> String {
        guard !specs.isEmpty,
              let expression = try? NSRegularExpression(pattern: "E12INLINE_*[0-9]+Z") else { return html }
        let bySentinel = Dictionary(specs.map { ($0.sentinel, $0.html) }, uniquingKeysWith: { first, _ in first })
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in expression.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let sentinel = source.substring(with: match.range)
            output += bySentinel[sentinel] ?? sentinel
            cursor = match.range.location + match.range.length
        }
        return output + source.substring(from: cursor)
    }
}
