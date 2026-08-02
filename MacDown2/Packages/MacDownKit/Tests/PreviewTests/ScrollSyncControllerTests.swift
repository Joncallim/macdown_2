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

    // Regression: without echo suppression, an editor-driven preview scroll
    // gets reported back by the preview's own scroll notification, which
    // would re-target the editor and bounce indefinitely.
    @Test func editorDrivenPreviewScrollIsNotEchoedBackToEditor() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)
        #expect(controller.targetPreviewFraction != nil)
        controller.targetPreviewFraction = nil

        // The preview reports the position it was just told to adopt (block 1
        // starts at content offset 10).
        controller.previewContentOffsetDidChange(10)

        #expect(controller.targetSourceLine == nil, "Echo of the editor-driven scroll must not bounce back")
    }

    /// Symmetric case for the reverse direction.
    @Test func previewDrivenEditorScrollIsNotEchoedBackToPreview() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.previewContentOffsetDidChange(10)
        #expect(controller.targetSourceLine != nil)
        controller.targetSourceLine = nil

        // The editor reports the line it was just told to adopt.
        controller.editorDidScroll(toLine: 3)

        #expect(controller.targetPreviewFraction == nil, "Echo of the preview-driven scroll must not bounce back")
    }

    @Test func genuineFollowUpScrollAfterEchoIsNotSuppressed() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)
        controller.targetPreviewFraction = nil
        controller.previewContentOffsetDidChange(10) // echo, swallowed
        #expect(controller.targetSourceLine == nil)

        // A real user scroll of the preview back to the top must still work
        // after the echo was swallowed once.
        controller.previewContentOffsetDidChange(0)
        #expect(controller.targetSourceLine == 1)
    }

    // Regression: one user gesture produces MANY position reports, not one —
    // SwiftUI's `onScrollGeometryChange` fires throughout a scroll, and AppKit
    // posts a bounds-change notification per frame of a smooth scroll. A
    // one-shot latch (clear-on-first-match) swallowed only the first echo and
    // let every subsequent one through, so a single drag in one pane bounced
    // back off the other as a scroll command and the two fought each other —
    // observed as the editor snapping away mid-scroll.
    @Test func repeatedEchoesAtTheSameBlockAreAllSuppressed() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)
        controller.targetPreviewFraction = nil

        // The preview reports settling on the same block repeatedly. Every one
        // of these is the same editor-driven sync, so none may bounce back.
        for _ in 0 ..< 5 {
            controller.previewContentOffsetDidChange(10)
            #expect(controller.targetSourceLine == nil, "Repeated echo of one gesture must not drive the editor")
        }

        // And the reverse direction, which oscillated the same way.
        controller.previewContentOffsetDidChange(0)
        #expect(controller.targetSourceLine == 1)
        controller.targetSourceLine = nil
        controller.targetPreviewFraction = nil

        for _ in 0 ..< 5 {
            controller.editorDidScroll(toLine: 1)
            #expect(controller.targetPreviewFraction == nil, "Repeated echo of one gesture must not drive the preview")
        }
    }

    // Regression: a debounced re-parse can replace `map` between an
    // editor-driven scroll request and the preview's echo of it. A block
    // index recorded against the old map must not be compared against block
    // indices resolved from the new one.
    @Test func mapChangeInvalidatesInFlightEchoSuppression() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        // Editor scrolls to block 1; controller now expects an echo at
        // content offset 10 (block 1's top edge) to be swallowed.
        controller.editorDidScroll(toLine: 3)
        controller.targetPreviewFraction = nil

        // A re-parse replaces the map (and heights) before that echo arrives.
        let newBlocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p0.5 (new)", lineRange: 2 ... 2),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 4 ... 4),
        ]
        controller.update(map: ScrollSyncMap(blocks: newBlocks))
        controller.update(blockHeights: [0: 10, 1: 5, 2: 20])

        // The stale echo, now resolved against the new map, must be treated
        // as a genuine preview scroll rather than silently swallowed.
        controller.previewContentOffsetDidChange(10)
        #expect(
            controller.targetSourceLine != nil,
            "Stale echo-suppression state must not swallow a real scroll after the map changed"
        )
    }
}
