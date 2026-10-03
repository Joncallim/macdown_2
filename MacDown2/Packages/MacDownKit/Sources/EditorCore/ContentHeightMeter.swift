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

        var total: CGFloat = 0
        Self.forEachParagraph(in: string) { range in
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
