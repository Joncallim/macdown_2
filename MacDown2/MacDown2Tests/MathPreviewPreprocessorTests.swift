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

    /// `PreviewBlock.blocks(from:text:)` is deliberately top-level-only
    /// (E07's own design — `PreviewBlock.swift`'s doc comment: "mirrors a
    /// top-level `MarkdownBlock`"), so a fenced code block nested inside a
    /// list item or block quote is never its own `PreviewBlock`; it is
    /// just plain text inside the ENCLOSING list/quote block's `source`
    /// string. `preprocessed(_ block:)`'s top-level `.codeBlock`/
    /// `.htmlBlock` skip (matching `MathContribution.excludedRanges(in:)`'s
    /// former scope, before this epic's own reconciliation pass fixed that
    /// side — epic-19-implementation.md §21) therefore never applies to
    /// this block at all, and `preprocess(source:)` has no fenced-code
    /// awareness within a block's own text — only `InlineCodeSpanScanner`
    /// for genuinely inline code. Reproduced directly: an INVALID
    /// math-like span inside a nested fence gets replaced with the visible
    /// warning marker, corrupting the code sample the user actually
    /// authored. This is a real, currently-unfixed defect discovered while
    /// verifying the Export-side fix's Preview counterpart — recorded here
    /// as evidence rather than assumed away, and tracked as a follow-up
    /// (see `RELEASE_EVIDENCE.md`'s E19 row): fixing it requires either
    /// giving `preprocess(source:)` its own fenced-code-block scanner (a
    /// new, non-trivial raw-text CommonMark fence detector, not a
    /// one-line completion like the Export-side fix) or changing
    /// `PreviewBlock`'s granularity (an E07 architectural decision this
    /// epic must not make unilaterally per EPIC_STANDARD.md's
    /// stop-and-escalate rule).
    @Test func preprocessCorruptsAnInvalidMathLikeSpanInsideAFencedCodeBlockNestedInAListItem() {
        // A single-line fence body is accidentally protected today: the SAME
        // `InlineCodeSpanScanner` this preprocessor also uses for genuine
        // inline code (`` `$x$` ``) happens to treat the fence's own two
        // ``` runs as if they were one giant inline code span, since that
        // scanner has no fenced-code awareness either — it just matches "a
        // run of N backticks, closed by the next run of exactly N, not
        // crossing a blank line." That incidental protection breaks the
        // moment the fence body has an internal blank line, below.
        let listBlockSource = "- item text\n\n  ```\n  literal code: $bad$ end\n  ```"
        let result = MathPreviewPreprocessor.preprocess(source: listBlockSource, isValid: { _ in false })
        #expect(!result.contains(MathPreviewPreprocessor.invalidMathMarker))
    }

    @Test func preprocessCorruptsAnInvalidMathLikeSpanInsideAFencedCodeBlockWithAnInternalBlankLine() {
        let listBlockSource = "- item text\n\n  ```\n  literal code:\n\n  $bad$ end\n  ```"
        let result = MathPreviewPreprocessor.preprocess(source: listBlockSource, isValid: { _ in false })
        // Documents a REAL, currently-unfixed defect (not the benign case
        // above): once the fence body has a blank line, the accidental
        // inline-code protection no longer applies, `preprocess` has no
        // other fenced-code awareness, and the invalid-math marker
        // corrupts the code sample the user actually authored. Tracked in
        // `RELEASE_EVIDENCE.md`'s E19 row as a follow-up, not fixed here —
        // see this test's suite-level doc comment for why.
        #expect(result.contains(MathPreviewPreprocessor.invalidMathMarker))
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
