import Foundation

/// UTF-16 ranges of CommonMark *fenced* code blocks (```` ``` ```` or `~~~`,
/// a run of 3 or more of the same character) in raw text — including ones
/// nested inside a list item or block quote, where `MarkdownEngine`'s own
/// block model has no visibility (it mirrors only top-level
/// `MarkdownBlock`s, see `epic-19-implementation.md` §2.1). Closes issue
/// #63: `MathPreviewPreprocessor` previously relied only on
/// `InlineCodeSpanScanner`'s coincidental protection (that scanner's own
/// "never crosses a blank line" rule happened to also stop most single-line
/// nested-fence bodies from being touched), which broke the moment a nested
/// fence's body contained an internal blank line.
///
/// A fence line is recognized after stripping leading whitespace (nested
/// content can be indented arbitrarily deep — unlike a top-level fence,
/// which CommonMark caps at 3 spaces, there is no such cap once inside a
/// list item/block quote's own indentation). A closing fence must use the
/// same character and be at least as long as the opening run, on a line
/// containing nothing else but that run and trailing whitespace — matching
/// CommonMark's own closing-fence rule. An unterminated fence (no matching
/// close before the text ends) extends to the end of the text, mirroring
/// how an unterminated fence behaves inside its actual container in a real
/// CommonMark parse.
public enum FencedCodeBlockScanner {
    public static func ranges(in text: String) -> [Range<Int>] {
        let nsText = text as NSString
        var result: [Range<Int>] = []
        var searchLocation = 0

        while searchLocation < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
            guard let fence = fenceMarker(in: nsText, lineRange: lineRange) else {
                searchLocation = NSMaxRange(lineRange)
                continue
            }

            let openStart = lineRange.location
            var cursor = NSMaxRange(lineRange)
            var closeEnd = nsText.length

            while cursor < nsText.length {
                let candidateLineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
                if isClosingFence(in: nsText, lineRange: candidateLineRange, matching: fence) {
                    closeEnd = NSMaxRange(candidateLineRange)
                    break
                }
                cursor = NSMaxRange(candidateLineRange)
            }

            result.append(openStart ..< closeEnd)
            searchLocation = closeEnd
        }

        return result
    }

    private struct Fence {
        let character: unichar
        let length: Int
    }

    private static let backtick: unichar = 0x60 // "`"
    private static let tilde: unichar = 0x7E // "~"
    private static let greaterThan: unichar = 0x3E // ">"

    /// A fence-open candidate: optional block-quote markers, leading
    /// whitespace, then a run of ≥3 of the same fence character. A backtick
    /// fence's remainder (the info string) must not itself contain a
    /// backtick, matching CommonMark's own rule (a backtick run inside the
    /// info string would ambiguously look like another fence delimiter); a
    /// tilde fence's info string has no such restriction.
    private static func fenceMarker(in nsText: NSString, lineRange: NSRange) -> Fence? {
        let lineEnd = contentEnd(of: nsText, lineRange: lineRange)
        var index = skipContainerMarkersAndWhitespace(in: nsText, from: lineRange.location, to: lineEnd)
        guard index < lineEnd else { return nil }

        let markerChar = nsText.character(at: index)
        guard markerChar == backtick || markerChar == tilde else { return nil }

        var length = 0
        while index < lineEnd, nsText.character(at: index) == markerChar {
            length += 1
            index += 1
        }
        guard length >= 3 else { return nil }

        if markerChar == backtick {
            while index < lineEnd {
                if nsText.character(at: index) == backtick {
                    return nil
                }
                index += 1
            }
        }

        return Fence(character: markerChar, length: length)
    }

    /// A closing-fence candidate: optional block-quote markers, leading
    /// whitespace, a run of the fence's own character at least as long as
    /// the opening run, then only trailing whitespace to the end of the
    /// line's actual content (excluding the line terminator itself).
    private static func isClosingFence(in nsText: NSString, lineRange: NSRange, matching fence: Fence) -> Bool {
        let lineEnd = contentEnd(of: nsText, lineRange: lineRange)
        var index = skipContainerMarkersAndWhitespace(in: nsText, from: lineRange.location, to: lineEnd)
        guard index < lineEnd else { return false }

        var length = 0
        while index < lineEnd, nsText.character(at: index) == fence.character {
            length += 1
            index += 1
        }
        guard length >= fence.length else { return false }

        while index < lineEnd {
            guard isWhitespace(nsText.character(at: index)) else { return false }
            index += 1
        }
        return true
    }

    /// Skips a `> ` (or bare `>`) block-quote marker — repeated, to tolerate
    /// more than one level of quote nesting — then any plain whitespace.
    /// Bare list-item indentation needs no special handling here: it is
    /// already just leading spaces, which the whitespace skip alone covers.
    private static func skipContainerMarkersAndWhitespace(in nsText: NSString, from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, isWhitespace(nsText.character(at: index)) {
            index += 1
        }
        while index < end, nsText.character(at: index) == greaterThan {
            index += 1
            if index < end, isWhitespace(nsText.character(at: index)) {
                index += 1
            }
            while index < end, isWhitespace(nsText.character(at: index)) {
                index += 1
            }
        }
        return index
    }

    /// `lineRange`'s own end, minus the trailing line terminator
    /// (`\n`, `\r`, or `\r\n`) it always includes — the terminator itself
    /// must never satisfy a "nothing but whitespace/fence-character" check.
    private static func contentEnd(of nsText: NSString, lineRange: NSRange) -> Int {
        var end = NSMaxRange(lineRange)
        if end > lineRange.location, nsText.character(at: end - 1) == 0x0A { // "\n"
            end -= 1
        }
        if end > lineRange.location, nsText.character(at: end - 1) == 0x0D { // "\r"
            end -= 1
        }
        return end
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 // space or tab
    }
}
