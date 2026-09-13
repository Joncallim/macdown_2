import Foundation
@testable import MacDown2
import Math
import MathRendering
import Preview
import Testing

@Suite("MathPreviewPreprocessor")
struct MathPreviewPreprocessorTests {
    @Test func leavesSourceWithNoMathUntouched() {
        let source = "Just a paragraph, no equations here."
        #expect(MathPreviewPreprocessor.preprocess(source: source) == source)
    }

    @Test func leavesAValidInlineEquationByteForByteUntouched() {
        let source = "The energy is $E = mc^2$."
        #expect(MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in true }) == source)
    }

    @Test func replacesAnInvalidSpanWithTheVisibleMarkerPreservingSurroundingText() {
        let source = "before $bad$ after"
        let result = MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in false })
        #expect(result == "before \(MathPreviewPreprocessor.invalidMathMarker) after")
    }

    @Test func onlyReplacesTheFlaggedSpanLeavingASiblingValidSpanAlone() {
        let source = "$bad$ then $good$"
        let result = MathPreviewPreprocessor.preprocess(source: source) { span in span.latex == "good" }
        #expect(result == "\(MathPreviewPreprocessor.invalidMathMarker) then $good$")
    }

    @Test func replacesMultipleInvalidSpansIndependently() {
        let source = "$a$ $b$ $c$"
        let result = MathPreviewPreprocessor.preprocess(source: source) { span in span.latex == "b" }
        let marker = MathPreviewPreprocessor.invalidMathMarker
        #expect(result == "\(marker) $b$ \(marker)")
    }

    @Test func stopsValidatingBeyondTheScannedSpanCapLeavingTheRestUntouched() {
        let manySpans = (0 ..< 300).map { "$s\($0)$" }.joined(separator: " ")
        var validationCount = 0
        _ = MathPreviewPreprocessor.preprocess(source: manySpans) { _ in
            validationCount += 1
            return false
        }
        #expect(validationCount == MathPreviewPreprocessor.maxScannedSpansPerBlock)
    }

    /// Uses a genuinely malformed span (confirmed against real `SwiftUIMath`
    /// parsing, matching the fixture already established in
    /// `MathImageRendererTests`/`MathContributionTests`) — a bare word like
    /// `"bad"` is NOT malformed LaTeX: SwiftUIMath happily typesets three
    /// adjacent implicit-multiplication variables from it.
    @Test func preprocessedBlockReusesTheSameIDWhenSourceIsRewritten() {
        let block = PreviewBlock(kind: .paragraph, source: "$\\frac{1}{$", lineRange: 1 ... 1)
        let rewritten = MathPreviewPreprocessor.preprocessed(block)
        #expect(rewritten.source != block.source)
        #expect(rewritten.id == block.id)
        #expect(rewritten.kind == block.kind)
        #expect(rewritten.lineRange == block.lineRange)
    }

    @Test func preprocessedBlockIsIdenticalWhenNoRewriteIsNeeded() {
        let block = PreviewBlock(kind: .paragraph, source: "no math", lineRange: 1 ... 1)
        #expect(MathPreviewPreprocessor.preprocessed(block) == block)
    }

    @Test func preprocessedPassesThroughNilBlocksArray() {
        #expect(MathPreviewPreprocessor.preprocessed(nil) == nil)
    }

    @Test func preprocessedMapsEveryBlockInAnArray() {
        let blocks = [
            PreviewBlock(kind: .paragraph, source: "$\\frac{1}{$", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "clean", lineRange: 2 ... 2),
        ]
        let result = MathPreviewPreprocessor.preprocessed(blocks)
        #expect(result?.count == 2)
        #expect(result?[0].source == MathPreviewPreprocessor.invalidMathMarker)
        #expect(result?[1].source == "clean")
    }

    /// Preview's half of the Preview/Export parity requirement
    /// (epic-19-implementation.md §2.1, §7.1) — the SAME corpus
    /// `MathImageRendererTests.isRenderableMatchesTheSharedParityCorpus`
    /// exercises on Export's side, run through Preview's real default
    /// validity check (`MathImageRenderer.isRenderable`, not a fake): a
    /// span this corpus calls renderable must NOT be flagged, and one it
    /// calls unrenderable MUST be flagged, wrapped in whichever delimiter
    /// its style requires.
    ///
    /// A corpus case with EMPTY `latex` is a special case, not a
    /// contradiction: `MathSpanScanner` (confirmed in
    /// `MathSpanScannerTests.scanTreatsALoneDoubleDollarWithNoContentAsUnmatchedText`/
    /// `scanTreatsFourConsecutiveDollarSignsAsUnmatchedText`) never scans an
    /// empty `$$`/`$$$$` as a span at all — there is nothing for this
    /// preprocessor to find and flag, so the source is correctly left
    /// unchanged regardless of `isRenderable`'s value for that entry. Those
    /// entries stay `isRenderable: false` in the shared corpus because they
    /// ARE unrenderable via a directly-constructed `MathSpan`
    /// (`MathImageRendererTests` exercises exactly that, reachable when
    /// some other producer builds a `MathSpan` without going through the
    /// scanner) — this test documents that the two paths reach different,
    /// both-correct outcomes for this one edge case.
    @Test(arguments: MathParityCorpus.cases)
    func preprocessMatchesTheSharedParityCorpusUsingTheRealValidityCheck(_ testCase: MathParityCorpus.Case) {
        let delimiter = testCase.style == .inline ? "$" : "$$"
        let source = "\(delimiter)\(testCase.latex)\(delimiter)"
        let result = MathPreviewPreprocessor.preprocess(source: source)
        if testCase.isRenderable || testCase.latex.isEmpty {
            #expect(result == source, "\(testCase.comment)")
        } else {
            #expect(result == MathPreviewPreprocessor.invalidMathMarker, "\(testCase.comment)")
        }
    }
}
