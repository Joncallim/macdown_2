import Foundation

/// UTF-16 ranges where `$…$` text is a literal part of Markdown syntax rather than
/// prose: link and image destinations, reference-definition destinations, autolinks
/// and bare URLs, and inline HTML tags.
///
/// `CMarkGFM` only substitutes math sentinels in TEXT nodes, so a span found inside
/// one of these ranges would reach the exported HTML as the sentinel string itself
/// (`href="…?a=E12INLINE0Z"`) instead of the author's characters.
public enum MathLiteralContextScanner {
    private static let patterns: [NSRegularExpression] = [
        #"\]\([^)\n]{0,2048}\)"#,
        #"(?m)^ {0,3}\[(?!\^)[^\]\n]+\]:[ \t]*(?:<[^>\n]*>|\S+)"#,
        #"<(?:https?|ftp|mailto):[^>\s]*>"#,
        #"\b(?:https?://|www\.)[^\s<]+"#,
        #"</?[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*/?>"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func ranges(in text: String) -> [Range<Int>] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { pattern in
            pattern.matches(in: text, range: whole).map { $0.range.location ..< ($0.range.location + $0.range.length) }
        }
    }

    /// `text` with every UTF-16 unit in `ranges` replaced by a neutral character, so
    /// offsets stay valid while nothing inside those ranges can open or close a span.
    public static func masked(_ text: String, ranges: [Range<Int>]) -> String {
        guard !ranges.isEmpty else { return text }
        var units = Array(text.utf16)
        for range in ranges {
            for index in range.clamped(to: 0 ..< units.count) {
                units[index] = 0xE000
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
