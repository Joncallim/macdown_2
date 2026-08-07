@testable import Preview
import Testing

@Suite("ScrollSyncController")
@MainActor
struct ScrollSyncControllerTests {
    @Test func previewFractionForFirstLineIsZero() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        #expect(controller.previewFraction(forLine: 1) == 0)
    }

    @Test func previewFractionAtSecondBlockStart() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        #expect(controller.previewFraction(forLine: 3) == 10.0 / 30.0)
    }

    @Test func lineForPreviewFractionRoundTrips() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 30]
        )

        let fraction = controller.previewFraction(forLine: 4)
        #expect(fraction != nil)
        #expect(controller.line(forPreviewFraction: fraction ?? 0) == 4)
    }

    @Test func emptyMapReturnsNoFraction() {
        let controller = ScrollSyncController()
        #expect(controller.previewFraction(forLine: 1) == nil)
        #expect(controller.line(forPreviewFraction: 0.5) == nil)
    }

    @Test func editorScrollPublishesPreviewFraction() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)

        #expect(controller.targetPreviewFraction == 10.0 / 30.0)
    }

    @Test func previewScrollPublishesTargetSourceLine() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        // Content offset 10 is exactly the start of block 1 (line 3).
        controller.previewContentOffsetDidChange(10)

        #expect(controller.targetSourceLine == 3)
    }

    // Regression: block heights are measured asynchronously by the preview, so
    // they are all zero before its first layout pass and again briefly after a
    // re-parse swaps the block list. With every height at zero the resolver's
    // running total never exceeds the reported offset, so it used to fall
    // through and name the LAST block for any offset — which the editor obeyed
    // by scrolling to the end of the document. Observed as the editor snapping
    // to the bottom and refusing to stay scrolled anywhere else.
    @Test func unmeasuredBlockHeightsDoNotResolveEveryScrollToTheLastBlock() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [:] // nothing measured yet
        )

        controller.previewContentOffsetDidChange(250)

        #expect(
            controller.targetSourceLine == nil,
            "With no measured heights there is no valid mapping; must not fall back to the last block"
        )

        // Once heights arrive the mapping works normally again.
        controller.update(blockHeights: [0: 10, 1: 20, 2: 30])
        controller.previewContentOffsetDidChange(10)
        #expect(controller.targetSourceLine == 3)
    }

    // Regression: the "all heights zero" guard above only covers the
    // all-or-nothing case. Blocks measure asynchronously and independently,
    // so it is entirely normal for SOME to be measured while others (often
    // whichever were rendered most recently — the very ones a user is likely
    // to be scrolling toward) are not. The old resolver accumulated an
    // unmeasured block's height as zero and kept walking, which silently
    // folded that block's entire true span into whichever LATER, already-
    // measured block it hit next — misattributing any offset that actually
    // belonged to the unmeasured block.
    //
    // This produced two symptoms that looked unrelated but shared this one
    // cause: scrolling the editor to line 1, whose block is still unmeasured
    // on a freshly typed document, resolved the preview's confirming echo to
    // some later already-measured block instead of block 0 — not recognized
    // as an echo, so it re-targeted the editor there ("scroll to top snaps to
    // the bottom"). And scrolling toward the very end — where the newest
    // blocks are least likely to have measured yet — could resolve the echo
    // to an earlier block than the true last one ("scroll wheel bounces back
    // above the end").
    @Test func unmeasuredBlockIsNotSkippedInFavorOfALaterMeasuredOne() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# A", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3), // unmeasured
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 2: 20] // block 1 has not measured yet
        )

        // Offset 15 is past block 0's known 10pt span. With block 1 unmeasured
        // there is no way to know whether 15 still falls inside it or past
        // it — but it is provably NOT inside block 2, which the old resolver
        // (treating block 1 as zero-width) would have reported instead.
        controller.previewContentOffsetDidChange(15)

        #expect(
            controller.targetSourceLine == 3,
            "Offset just past block 0 must resolve to the unmeasured block 1, not skip ahead to block 2"
        )
    }
}
