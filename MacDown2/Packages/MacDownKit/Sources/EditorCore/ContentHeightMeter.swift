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
    private static let maximumCachedParagraphs = 50000
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
                total += estimator.height(ofParagraphLength: range.length)
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

/// A wrap-aware height estimate for text too large to measure: lines per paragraph from its length and the average
/// advance of the font, times the font's line height.
struct LineHeightEstimator {
    private let lineHeight: CGFloat
    private let charactersPerLine: CGFloat

    init(width: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        lineHeight = ceil(font.ascender - font.descender + font.leading)
        let advance = ("n" as NSString).size(withAttributes: [.font: font]).width
        charactersPerLine = max(1, (width / max(advance, 1)).rounded(.down))
    }

    func height(ofParagraphLength length: Int) -> CGFloat {
        let lines = max(1, (CGFloat(length) / charactersPerLine).rounded(.up))
        return lines * lineHeight
    }
}
