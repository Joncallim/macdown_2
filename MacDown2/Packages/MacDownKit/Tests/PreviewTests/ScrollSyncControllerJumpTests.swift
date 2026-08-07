@testable import Preview
import Testing

@Suite("ScrollSyncController jump")
@MainActor
struct ScrollSyncControllerJumpTests {
    @Test func jumpPublishesAnAnimatedPreviewTarget() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.jump(toLine: 3)

        #expect(controller.targetPreviewFraction == 10.0 / 30.0)
        #expect(controller.animatesNextPreviewScroll)
    }

    @Test func blockIndexAndLocalProgressResolvesThePositionWithinTheBlock() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        // Fraction 0.5 -> offset 15, which is 5pt into block 1 (offset 10...30).
        let midway = controller.blockIndexAndLocalProgress(forFraction: 0.5)
        #expect(midway?.blockIndex == 1)
        #expect(midway?.localProgress == 0.25)

        // Fraction 1.0 -> offset 30, the very end of block 1.
        let end = controller.blockIndexAndLocalProgress(forFraction: 1.0)
        #expect(end?.blockIndex == 1)
        #expect(end?.localProgress == 1.0)
    }

    @Test func blockIndexAndLocalProgressIsNilWithoutMeasuredHeights() {
        let controller = ScrollSyncController()
        #expect(controller.blockIndexAndLocalProgress(forFraction: 0.5) == nil)
    }

    // Regression: a non-zero `scrollTo(_:anchor:)` anchor on a block that
    // fits within the viewport produces a resulting content offset *above*
    // the block's own top (see `previewScrollTarget`'s doc comment for the
    // formula), which reads back as an earlier block than the one requested
    // and defeats echo suppression — the reported "scroll wheel bounces back
    // to the top" during ordinary, non-overflowing scroll-sync.
    @Test func previewScrollTargetUsesTopAnchorWhenTheBlockFitsTheViewport() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20] // block 1 is 20pt tall
        )

        // Fraction 0.5 -> offset 15, 5pt into block 1 (localProgress 0.25).
        // The viewport (800pt) is far taller than block 1, so the anchor
        // must be forced to 0 rather than the raw 0.25 localProgress.
        let target = controller.previewScrollTarget(forFraction: 0.5, viewportHeight: 800)
        #expect(target?.blockIndex == 1)
        #expect(target?.anchorY == 0)
    }

    // Regression: `editorDidScroll` used to publish only `targetPreviewFraction`
    // (offsetUpTo(blockIndex) / total), and the view recovered the block back
    // via `blockIndexAndLocalProgress(forFraction:)` (fraction * total). That
    // round trip is lossy — these specific heights are a real case (found by
    // brute-force search, not contrived) where `fraction * total` lands one
    // ULP *below* `offsetUpTo(1)`, which resolves to block 0 instead of the
    // intended block 1. Reproduced live as the editor scrolling toward the
    // end of a long document: the preview snapped to the block *before* the
    // one the editor asked for, its echo didn't match the latch, and the
    // editor was yanked backward — "the scroll wheel bounces back". Verified
    // this test fails (`targetPreviewBlock` absent, so callers fall back to
    // the lossy fraction round trip) without `targetPreviewBlock`.
    @Test func editorDidScrollPublishesAPreciseBlockThatSurvivesTheFractionRoundTrip() throws {
        let heights: [Int: Double] = [
            0: 948.9998098108642,
            1: 614.1235257124556,
            2: 71.24526057733623,
        ]
        let blocks = [
            PreviewBlock(kind: .paragraph, source: "p0", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let controller = ScrollSyncController(map: ScrollSyncMap(blocks: blocks), blockHeights: heights)

        controller.editorDidScroll(toLine: 3) // the very top of block 1

        // The lossy round trip a caller without `targetPreviewBlock` would
        // have to fall back to actually reproduces the bug here — confirming
        // this fixture triggers it, not just that the precise field exists.
        let fraction = try #require(controller.targetPreviewFraction)
        let roundTripped = try #require(controller.blockIndexAndLocalProgress(forFraction: fraction))
        #expect(roundTripped.blockIndex == 0, "Fixture sanity check: the fraction round trip must land one block early")

        // The precise target sidesteps that entirely.
        #expect(controller.targetPreviewBlock == PreviewBlockTarget(blockIndex: 1, localProgress: 0))

        // And `previewScrollTarget` resolves correctly once it's handed that
        // precise target, where it would resolve to the wrong block without one.
        let withoutPrecise = controller.previewScrollTarget(forFraction: fraction, viewportHeight: 800)
        #expect(withoutPrecise?.blockIndex == 0, "Fixture sanity check, same as above")

        let withPrecise = controller.previewScrollTarget(
            forFraction: fraction,
            viewportHeight: 800,
            preciseBlock: controller.targetPreviewBlock
        )
        #expect(withPrecise?.blockIndex == 1)
    }

    @Test func previewScrollTargetUsesProportionalAnchorWhenTheBlockOverflowsTheViewport() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 2000] // block 1 is much taller than the viewport
        )

        // Fraction 0.5 -> offset 1005, 995pt into block 1 (localProgress ~0.4975).
        let target = controller.previewScrollTarget(forFraction: 0.5, viewportHeight: 800)
        #expect(target?.blockIndex == 1)
        #expect(target?.anchorY == 995.0 / 2000.0)
    }

    // Regression: an *animated* jump reports many intermediate positions
    // along the way on both sides (AppKit posts a bounds-change notification
    // per animation frame; SwiftUI's `onScrollGeometryChange` does the same).
    // Without suppressing them, each side would read the other's
    // still-in-flight position as a fresh, genuine scroll and chase it —
    // fighting the very animation `jump(toLine:)` just started.
    @Test func jumpSuppressesReportsDuringTheSettleWindow() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        var clockInstant = ContinuousClock.now
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20, 2: 30],
            now: { clockInstant }
        )

        controller.jump(toLine: 5) // -> block 2, targets the far end
        controller.targetPreviewFraction = nil

        // A mid-animation frame reports the editor still partway there.
        controller.editorDidScroll(toLine: 1)
        #expect(controller.targetPreviewFraction == nil, "A report during the settle window must be ignored")

        // Likewise for the preview mid-animating toward its own target.
        controller.previewContentOffsetDidChange(0)
        #expect(controller.targetSourceLine == nil, "A report during the settle window must be ignored")

        // Advance partway through the window — still suppressed.
        clockInstant = clockInstant.advanced(by: .milliseconds(100))
        controller.editorDidScroll(toLine: 1)
        #expect(controller.targetPreviewFraction == nil, "Still inside the settle window")
    }

    @Test func jumpSuppressionExpiresAfterTheSettleWindow() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        var clockInstant = ContinuousClock.now
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20, 2: 30],
            now: { clockInstant }
        )

        controller.jump(toLine: 5)
        controller.targetPreviewFraction = nil

        // The animation has long since settled by now.
        clockInstant = clockInstant.advanced(by: .milliseconds(500))

        controller.editorDidScroll(toLine: 1)
        #expect(
            controller.targetPreviewFraction != nil,
            "A genuine scroll after the settle window has elapsed must go through normally"
        )
    }
}
