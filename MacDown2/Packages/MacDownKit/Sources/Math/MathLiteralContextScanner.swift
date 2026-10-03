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
        #"(?m)^ {0,3}\[(?!\^)[^\]\n]+\]:[ \t]*(?:<[^>\n]*>|\S+)"#,
        #"<(?:https?|ftp|mailto):[^>\s]*>"#,
        #"\b(?:https?://|www\.)[^\s<]+"#,
        #"</?[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*/?>"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func ranges(in text: String) -> [Range<Int>] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return linkDestinationRanges(in: text) + patterns.flatMap { pattern in
            pattern.matches(in: text, range: whole).map { $0.range.location ..< ($0.range.location + $0.range.length) }
        }
    }

    private static let maximumDestinationLength = 2048

    /// `](…)` spans of at most 2048 non-`)`, non-newline units. Hand-scanned because the equivalent
    /// bounded regex re-scans up to 2048 units from every `](` of an unclosed run; a forward-only
    /// cursor to the next `)` or newline keeps the whole pass linear.
    private static func linkDestinationRanges(in text: String) -> [Range<Int>] {
        let units = Array(text.utf16)
        let count = units.count
        var result: [Range<Int>] = []
        var index = 0
        var stop = 0
        while index + 1 < count {
            guard units[index] == 0x5D, units[index + 1] == 0x28 else { index += 1; continue }
            let contentStart = index + 2
            if stop < contentStart {
                stop = contentStart
            }
            while stop < count, units[stop] != 0x29, units[stop] != 0x0A {
                stop += 1
            }
            if stop < count, units[stop] == 0x29, stop - contentStart <= maximumDestinationLength {
                result.append(index ..< stop + 1)
                index = stop + 1
            } else {
                index += 1
            }
        }
        return result
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
