import Foundation

/// UTF-16 ranges of CommonMark inline code spans (`` `...` ``, ```` ``...`` ````,
/// and so on) in raw text — a run of N backtick characters, closed by the
/// NEXT run of exactly N backticks (a shorter or longer run does not close
/// it, matching CommonMark's own rule); a span search never crosses a blank
/// line (two or more consecutive newlines), since CommonMark inline spans
/// never do either.
///
/// Adversarial-review finding (post-merge, `chatgpt-codex-connector`):
/// `MathContribution.excludedRanges(in:)` only excludes TOP-LEVEL code/HTML
/// *blocks* — it has no way to see an inline code span living inside an
/// ordinary paragraph, since `MarkdownEngine` has no inline-node model at
/// all (epic-19-implementation.md §2.1). A `$`-looking pattern inside
/// inline code (`` `$x$` ``) was therefore still treated as math: cmark
/// places that authored text inside a `CODE` node, but `CMarkGFM`'s
/// sentinel substitution only rewrites `TEXT` nodes, so the exported
/// document showed the literal, meaningless sentinel string in place of the
/// author's code — not merely a wrong rendering, active content
/// corruption. `MathPreviewPreprocessor` has the analogous, narrower risk:
/// rewriting content inside a code span (flagging it invalid, or collapsing
/// its newlines) before Textual's own real, correct inline-code skip
/// (`PatternProcessor.expand`'s `isPreformatted` check, which does cover
/// inline code) ever gets a chance to protect it.
public enum InlineCodeSpanScanner {
    public static func ranges(in text: String) -> [Range<Int>] {
        let units = Array(text.utf16)
        var result: [Range<Int>] = []
        var index = 0

        while index < units.count {
            guard units[index] == backtick else {
                index += 1
                continue
            }

            let openStart = index
            var openLength = 0
            while index < units.count, units[index] == backtick {
                openLength += 1
                index += 1
            }

            if let closeStart = closingRunStart(units, from: index, length: openLength) {
                result.append(openStart ..< (closeStart + openLength))
                index = closeStart + openLength
            }
            // No matching closing run: an unmatched backtick run is not a
            // code span (CommonMark) — `index` already sits just past it,
            // so scanning simply continues from there.
        }

        return result
    }

    private static let backtick: UInt16 = 0x60 // "`"
    private static let newline: UInt16 = 0x0A // "\n"

    /// The UTF-16 offset where a run of exactly `length` backticks starts,
    /// searching from `start`, or `nil` if none is found before a blank
    /// line (two consecutive newlines) or the end of `units`.
    private static func closingRunStart(_ units: [UInt16], from start: Int, length: Int) -> Int? {
        var index = start
        var consecutiveNewlines = 0

        while index < units.count {
            if units[index] == newline {
                consecutiveNewlines += 1
                if consecutiveNewlines >= 2 {
                    return nil
                }
                index += 1
                continue
            }
            consecutiveNewlines = 0

            guard units[index] == backtick else {
                index += 1
                continue
            }

            let runStart = index
            var runLength = 0
            while index < units.count, units[index] == backtick {
                runLength += 1
                index += 1
            }
            if runLength == length {
                return runStart
            }
        }

        return nil
    }
}
