import Foundation

// MARK: - UTF-16 / scalar primitives

extension MarkdownEditingAssistEngine {
    static func character(at index: Int, in text: NSString) -> unichar {
        text.character(at: index)
    }

    static func isDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }

    static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    /// The scalar ending at `index` (the previous character), handling
    /// surrogate halves as one scalar.
    static func scalar(before index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index > 0, index <= text.length else { return nil }
        var start = index - 1
        var length = 1
        let unit = text.character(at: start)
        if unit >= 0xDC00, unit <= 0xDFFF, start > 0 {
            let high = text.character(at: start - 1)
            if high >= 0xD800, high <= 0xDBFF {
                start -= 1
                length = 2
            }
        }
        return leadingScalar(in: text, at: start, length: length)
    }

    /// The scalar starting at `index`.
    static func scalar(at index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index >= 0, index < text.length else { return nil }
        let unit = text.character(at: index)
        let length = (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) ? 2 : 1
        return leadingScalar(in: text, at: index, length: length)
    }

    private static func leadingScalar(in text: NSString, at index: Int, length: Int) -> Unicode.Scalar? {
        let substring = text.substring(with: NSRange(location: index, length: length))
        return String(substring).unicodeScalars.first
    }

    static func utf16Length(of scalar: Unicode.Scalar) -> Int {
        scalar.value > 0xFFFF ? 2 : 1
    }

    /// Boundary classification for pair completion. Emoji/CJK neighbors are
    /// ordinary non-boundary text unless the actual scalar is classified as
    /// whitespace/control or Unicode punctuation (P*).
    static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control:
            true
        case .closePunctuation, .connectorPunctuation, .dashPunctuation,
             .finalPunctuation, .initialPunctuation, .openPunctuation, .otherPunctuation:
            true
        default:
            false
        }
    }

    /// Clamps a requested range to `0...length`.
    static func clampedRange(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}

// MARK: - Line geometry

extension MarkdownEditingAssistEngine {
    /// Start of the line containing `location` (a location exactly at a
    /// newline belongs to the line the newline terminates).
    static func lineStart(of location: Int, in text: NSString) -> Int {
        var index = min(max(0, location), text.length)
        while index > 0 {
            let previous = index - 1
            let unit = character(at: previous, in: text)
            if unit == 0x0A {
                break
            }
            // A lone CR ends a line too (NSTextView's paragraph separator); a CR directly before an LF is the
            // first half of a CRLF pair, so a caret between the two still belongs to the earlier line.
            if unit == 0x0D, !(index < text.length && character(at: index, in: text) == 0x0A) {
                break
            }
            index = previous
        }
        return index
    }

    /// End of the line content containing `location`, excluding the trailing
    /// line separator (a single `\n`, a lone `\r`, or the `\r\n` pair).
    static func lineContentEnd(of location: Int, in text: NSString) -> Int {
        var index = min(max(0, location), text.length)
        while index < text.length {
            let unit = character(at: index, in: text)
            if unit == 0x0A {
                break
            }
            if unit == 0x0D { // CRLF pair or lone CR: either way the content ends here
                break
            }
            index += 1
        }
        return index
    }

    /// The separator to insert for a new line after the line containing
    /// `location`, so Enter never introduces a second line-ending convention
    /// into a document (invariant #5): the line's own `\r\n` or `\n` when it
    /// has one; otherwise (the last line, or a bare-CR document this engine
    /// sees as one line) the nearest terminator before `location`, then the
    /// nearest after it, and only then `"\n"` for text with no terminator.
    static func lineSeparator(ofLineContaining location: Int, in text: NSString) -> String {
        let contentEnd = lineContentEnd(of: location, in: text)
        if contentEnd < text.length {
            if character(at: contentEnd, in: text) == 0x0A {
                return "\n"
            }
            let isCRLF = contentEnd + 1 < text.length && character(at: contentEnd + 1, in: text) == 0x0A
            return isCRLF ? "\r\n" : "\r"
        }
        var index = min(max(0, location), text.length)
        while index > 0 {
            index -= 1
            if let found = terminator(endingAt: index, in: text) {
                return found
            }
        }
        index = min(max(0, location), text.length)
        while index < text.length {
            if let found = terminator(endingAt: index, in: text) {
                return found
            }
            index += 1
        }
        return "\n"
    }

    /// The terminator whose last unit is at `index`, if any: `\n` (or `\r\n`
    /// when preceded by `\r`), or a lone `\r` not followed by `\n`.
    private static func terminator(endingAt index: Int, in text: NSString) -> String? {
        switch character(at: index, in: text) {
        case 0x0A:
            return index > 0 && character(at: index - 1, in: text) == 0x0D ? "\r\n" : "\n"
        case 0x0D:
            let followedByLF = index + 1 < text.length && character(at: index + 1, in: text) == 0x0A
            return followedByLF ? nil : "\r"
        default:
            return nil
        }
    }

    static func firstNonWhitespace(in text: NSString, from start: Int, to end: Int) -> Int? {
        // Direct UTF-16 unit scan. Space/tab are BMP singles, and any astral
        // scalar's high surrogate is itself non-whitespace, so the first
        // non-space/tab unit is exactly the first non-whitespace scalar.
        // Bridging each scanned unit through a temporary Swift `String` (the
        // previous implementation) made a 2 MB whitespace line cost ~100 ns
        // per unit; `character(at:)` keeps the scan proportional without
        // per-unit allocation.
        var index = max(0, start)
        while index < end {
            let unit = character(at: index, in: text)
            if unit != 0x20, unit != 0x09 {
                return index
            }
            index += 1
        }
        return nil
    }
}
