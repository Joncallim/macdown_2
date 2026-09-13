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

    @Test func leavesAValidSingleLineDisplayEquationByteForByteUntouched() {
        let source = "$$\\frac{1}{2}+\\sqrt{2}$$"
        #expect(MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in true }) == source)
    }

    /// Confirmed via real Release-app dogfood (epic-19-implementation.md
    /// §17 Slice 3 as-built note): Textual's `PatternProcessor` tokenizes
    /// each `AttributedString` run separately, and Foundation's Markdown
    /// parser puts each soft-line-broken line of a paragraph in its own
    /// run — so a `$$` spanning multiple lines is invisible to Textual's
    /// tokenizer even though `MathSpanScanner` (and Export's
    /// `MathContribution`) both already handle it correctly. Collapsing the
    /// internal newlines to spaces is what fixes this, since LaTeX math
    /// mode assigns no meaning to that whitespace.
    @Test func collapsesInternalNewlinesInAValidMultiLineDisplayEquation() {
        let source = "$$\n\\frac{1}{2}+\\sqrt{2}\n$$"
        let result = MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in true })
        #expect(result == "$$ \\frac{1}{2}+\\sqrt{2} $$")
        #expect(!result.contains("\n"))
    }

    @Test func collapsesOnlyTheMultiLineSpanLeavingSurroundingTextAndOtherSpansAlone() {
        let source = "before\n\n$$\nfoo\n$$\n\nafter $x=1$ end"
        let result = MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in true })
        #expect(result == "before\n\n$$ foo $$\n\nafter $x=1$ end")
    }

    /// A malformed multi-line span is flagged, not newline-collapsed —
    /// `isValid` is checked first, so a span never gets both treatments.
    @Test func flagsAMalformedMultiLineSpanRatherThanCollapsingIt() {
        let source = "$$\nbad\n$$"
        let result = MathPreviewPreprocessor.preprocess(source: source, isValid: { _ in false })
        #expect(result == MathPreviewPreprocessor.invalidMathMarker)
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

    /// Adversarial-review finding (epic-19-implementation.md §18): a code
    /// block must never be touched by this preprocessor, even when its
    /// content happens to scan as a "malformed" math span — otherwise the
    /// displayed code content itself would be corrupted with the invalid-
    /// math marker.
    @Test func preprocessedNeverRewritesACodeBlockEvenWithMathLikeContent() {
        let block = PreviewBlock(kind: .codeBlock(language: nil), source: "price is $5, $10", lineRange: 1 ... 1)
        #expect(MathPreviewPreprocessor.preprocessed(block) == block)
    }

    @Test func preprocessedNeverRewritesAnHTMLBlockEvenWithMathLikeContent() {
        let block = PreviewBlock(kind: .htmlBlock, source: "<div>$5, $10</div>", lineRange: 1 ... 1)
        #expect(MathPreviewPreprocessor.preprocessed(block) == block)
    }

    @Test func preprocessedStillRewritesAnOrdinaryParagraphWithMalformedMath() {
        let block = PreviewBlock(kind: .paragraph, source: "$\\frac{1}{$ here", lineRange: 1 ... 1)
        let result = MathPreviewPreprocessor.preprocessed(block)
        #expect(result.source != block.source)
        #expect(result.source.contains(MathPreviewPreprocessor.invalidMathMarker))
    }
}
