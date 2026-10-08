import AppKit

/// Measures the height a document needs when wrapped to a width, paragraph by paragraph.
///
/// `NSString.boundingRect` over the WHOLE document is quadratic for non-Latin or mixed-script
/// text (Release builds: 250 lines of Japanese+emoji 2 s, 1000 lines 35 s) and it ran on the
/// main thread 50 ms after every edit. Paragraphs stack, so the document height is the sum of
/// its paragraphs' heights (an empty paragraph is one line) — the same number, measured in
/// linear time, and cached per paragraph so an edit re-measures only the paragraph it touched.
@MainActor
final class ContentHeightMeter {
    private var cacheKey = ""
    private var heights: [Int: CGFloat] = [:]
    private static let maximumCachedParagraphs = 250_000
    /// UTF-16 units above which the whole document is estimated rather than measured.
    static let estimationThreshold = 1_000_000
    static let maximumMeasuredParagraphLength = 20000

    func height(of string: NSString, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let key = Self.cacheKey(width: width, attributes: attributes)
        if key != cacheKey || heights.count > Self.maximumCachedParagraphs {
            cacheKey = key
            heights.removeAll(keepingCapacity: true)
        }
        let size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        func measure(_ paragraph: NSString) -> CGFloat {
            paragraph.boundingRect(
                with: size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height
        }

        let estimator = LineHeightEstimator(width: width, attributes: attributes)
        let estimatesEverything = string.length > Self.estimationThreshold
        var total: CGFloat = 0
        Self.forEachParagraph(in: string) { range in
            // Measuring is O(document) after every edit pause and quadratic inside one long CJK/emoji paragraph, so
            // a huge document, or a huge paragraph, is sized from its length instead (a 10 MB file stalled the main
            // thread for ~0.7 s per pause; one 400k-character CJK paragraph for ~24 s).
            if estimatesEverything || range.length > Self.maximumMeasuredParagraphLength {
                total += estimator.height(of: string, range: range)
                return
            }
            let paragraph = string.substring(with: range)
            let hash = paragraph.hashValue
            if let cached = heights[hash] {
                total += cached
                return
            }
            let measured = measure(paragraph as NSString)
            heights[hash] = measured
            total += measured
        }
        return total
    }

    /// Calls `body` with each paragraph's range (terminator excluded), INCLUDING empty ones and
    /// the empty paragraph after a trailing terminator. A paragraph ends at `\n`, `\r`, `\r\n` or
    /// U+2029.
    static func forEachParagraph(in string: NSString, _ body: (NSRange) -> Void) {
        let length = string.length
        var start = 0
        var index = 0
        while index < length {
            let unit = string.character(at: index)
            if unit == 0x0A || unit == 0x0D || unit == 0x2029 {
                body(NSRange(location: start, length: index - start))
                if unit == 0x0D, index + 1 < length, string.character(at: index + 1) == 0x0A {
                    index += 1
                }
                index += 1
                start = index
            } else {
                index += 1
            }
        }
        body(NSRange(location: start, length: length - start))
    }

    private static func cacheKey(width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        let font = (attributes[.font] as? NSFont).map { "\($0.fontName)-\($0.pointSize)" } ?? "nofont"
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle).map { "\($0)" } ?? "nostyle"
        return "\(width)|\(font)|\(style)"
    }
}

/// A wrap-aware height estimate for text too large to measure. It deliberately OVER-estimates: an estimate that is
/// too short leaves the end of the document unreachable (the frame is shorter than the layout), while one that is too
/// long only adds blank space below the last line.
///
/// The line height is measured from the real attributes, so a paragraph style's `lineHeightMultiple`/spacing counts.
/// Width is summed per UTF-16 unit: ASCII at the font's average advance, everything else (CJK, emoji, surrogate
/// halves) at most of an em, which is what wide scripts need.
struct LineHeightEstimator {
    private let lineHeight: CGFloat
    private let availableWidth: CGFloat
    private let asciiAdvance: CGFloat
    private let wideAdvance: CGFloat
    /// Word wrapping leaves ragged lines, so real layouts use somewhat more lines than width / width.
    private static let wrappingSlack: CGFloat = 1.08

    init(width: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var measuring = attributes
        measuring[.font] = font
        lineHeight = ceil(("Ag" as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: measuring
        ).height)
        availableWidth = max(width, 1)
        asciiAdvance = max(("n" as NSString).size(withAttributes: [.font: font]).width, 1)
        wideAdvance = max(font.pointSize * 0.95, asciiAdvance)
    }

    func height(of string: NSString, range: NSRange) -> CGFloat {
        var ascii = 0
        var other = 0
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            if string.character(at: index) < 0x80 {
                ascii += 1
            } else {
                other += 1
            }
            index += 1
        }
        let totalWidth = CGFloat(ascii) * asciiAdvance + CGFloat(other) * wideAdvance
        let lines = max(1, (totalWidth * Self.wrappingSlack / availableWidth).rounded(.up))
        return lines * lineHeight
    }
}
