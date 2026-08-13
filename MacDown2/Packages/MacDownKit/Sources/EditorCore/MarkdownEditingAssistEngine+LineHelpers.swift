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
            if character(at: previous, in: text) == 0x0A {
                break
            }
            index = previous
        }
        return index
    }

    /// End of the line content containing `location`, excluding the trailing
    /// line separator (a single `\n` or the `\r\n` pair).
    static func lineContentEnd(of location: Int, in text: NSString) -> Int {
        var index = min(max(0, location), text.length)
        while index < text.length {
            let unit = character(at: index, in: text)
            if unit == 0x0A {
                break
            }
            if unit == 0x0D, index + 1 < text.length, character(at: index + 1, in: text) == 0x0A {
                break
            }
            index += 1
        }
        return index
    }

    /// The line separator following the line containing `location`:
    /// `"\r\n"` when the line has an observable CRLF separator, else `"\n"`.
    static func lineSeparator(ofLineContaining location: Int, in text: NSString) -> String {
        let contentEnd = lineContentEnd(of: location, in: text)
        if contentEnd + 1 < text.length,
           character(at: contentEnd, in: text) == 0x0D,
           character(at: contentEnd + 1, in: text) == 0x0A
        // swiftlint:disable:next opening_brace
        {
            return "\r\n"
        }
        return "\n"
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
