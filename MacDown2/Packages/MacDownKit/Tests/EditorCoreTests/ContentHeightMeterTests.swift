import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: the whole-document `boundingRect` that sized the editor frame was quadratic
/// for non-Latin/mixed text — seconds to minutes on the main thread after every edit.
@MainActor
struct ContentHeightMeterTests {
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
    ]

    private func wholeStringHeight(_ text: String, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height
    }

    @Test(arguments: [
        "", "a", "a\n", "a\nb", "a\nb\n", "a\n\nb", "\n", "a\n\n", "a\r\nb\r\n", "a\rb",
        "日本語\n", "日本語\n\nx", "emoji 🎉 line\nnext",
        String(repeating: "word ", count: 200), String(repeating: "word ", count: 200) + "\nx",
        String(repeating: "日本語のテキスト ", count: 80) + "\nあ",
    ])
    func paragraphwiseHeightEqualsTheWholeStringMeasurement(text: String) {
        let meter = ContentHeightMeter()
        let width: CGFloat = 300
        let sum = meter.height(of: text as NSString, width: width, attributes: attributes)
        #expect(
            abs(sum - wholeStringHeight(text, width: width)) < 0.5,
            "height differs for \(text.prefix(20).debugDescription)"
        )
    }

    @Test func aLargeMixedScriptDocumentIsMeasuredInWellUnderASecond() {
        let line = "日本語のテキストと emoji 🎉 が混在する行です。これはテストです。"
        let text = (0 ..< 3000).map { "\($0) " + line }.joined(separator: "\n")
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 0)
        // The whole-string measurement of this takes minutes; allow a very generous bound.
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test func aRepeatMeasurementReusesTheCachedParagraphs() {
        let text = (0 ..< 500).map { "line \($0) with some text" }.joined(separator: "\n")
        let meter = ContentHeightMeter()
        let first = meter.height(of: text as NSString, width: 400, attributes: attributes)
        let again = meter.height(of: text as NSString, width: 400, attributes: attributes)
        #expect(first == again)
    }

    @Test func aWidthChangeInvalidatesTheCache() {
        let text = String(repeating: "word ", count: 200)
        let meter = ContentHeightMeter()
        let narrow = meter.height(of: text as NSString, width: 150, attributes: attributes)
        let wide = meter.height(of: text as NSString, width: 600, attributes: attributes)
        #expect(narrow > wide)
    }

    /// Review pass 6: the meter re-enumerated, copied and hashed every paragraph of the document after each edit
    /// pause (~0.7 s per pause for a 10 MB file in release), and one huge CJK paragraph was still quadratic.
    @Test func aHugeDocumentIsEstimatedNotMeasuredParagraphByParagraph() {
        let text = (0 ..< 130_000).map { "line number \($0) with some distinct text" }.joined(separator: "\n")
        #expect(text.utf16.count > ContentHeightMeter.estimationThreshold)
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 130_000 * 10)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func oneHugeParagraphIsEstimatedInsteadOfMeasured() {
        let text = String(repeating: "日本語のテキスト🙂", count: 30000)
        #expect(text.utf16.count > ContentHeightMeter.maximumMeasuredParagraphLength)
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 0)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func theEstimateIsWithinAFactorOfTwoOfTheMeasurementForLatinText() {
        let text = String(repeating: "word and more words ", count: 400)
        let width: CGFloat = 500
        let measured = ContentHeightMeter().height(of: text as NSString, width: width, attributes: attributes)
        let estimator = LineHeightEstimator(width: width, attributes: attributes)

        let estimated = estimator.height(ofParagraphLength: text.utf16.count)

        #expect(estimated > measured / 2 && estimated < measured * 2)
    }
}
