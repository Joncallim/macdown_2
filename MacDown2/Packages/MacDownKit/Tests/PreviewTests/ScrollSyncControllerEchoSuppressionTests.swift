@testable import Preview
import Testing

@Suite("ScrollSyncController echo suppression")
@MainActor
struct ScrollSyncControllerEchoSuppressionTests {
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

    // Regression: a continuous mouse-wheel scroll fires `editorDidScroll`
    // many times per second. Each call overwrites the sticky latch with the
    // newest requested block before an older request's async preview echo
    // has come back. Once that echo names a block that is no longer the
    // latest latch, an exact-match-only check let it through as a "genuine"
    // preview scroll and re-targeted the editor to the OLDER, already-passed
    // block — visibly fighting the user's still-active wheel gesture.
    @Test func rapidSuccessiveEditorScrollsSuppressStaleEchoOfEarlierRequest() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20, 2: 30]
        )

        // Block 1's request is still "in flight" (no echo yet) when block 2's
        // request overwrites the sticky latch.
        controller.editorDidScroll(toLine: 3) // -> block 1
        controller.targetPreviewFraction = nil
        controller.editorDidScroll(toLine: 5) // -> block 2, latch is now 2
        controller.targetPreviewFraction = nil

        // The preview's belated echo for the OLDER request (block 1's top
        // edge, offset 10) arrives after being overtaken.
        controller.previewContentOffsetDidChange(10)

        #expect(
            controller.targetSourceLine == nil,
            "A stale echo of a superseded in-flight request must not bounce the editor backward"
        )
    }

    /// Regression counterpart: recent-request suppression must not become
    /// permanent. A block that was requested once, long ago, must not
    /// silently swallow a genuine later scroll back to it.
    @Test func echoSuppressionDoesNotOutlastItsWindow() {
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

        controller.editorDidScroll(toLine: 3) // -> block 1
        controller.targetPreviewFraction = nil
        controller.editorDidScroll(toLine: 5) // -> block 2, latch is now 2
        controller.targetPreviewFraction = nil

        // Advance well past the suppression window before block 1's stale
        // echo arrives.
        clockInstant = clockInstant.advanced(by: .milliseconds(500))

        controller.previewContentOffsetDidChange(10) // block 1's stale echo

        #expect(
            controller.targetSourceLine == 3,
            "An echo arriving after the window elapsed must be treated as genuine, not swallowed forever"
        )
    }

    /// Regression guard for the fix above: recent-request suppression must
    /// key on the SPECIFIC block index requested, not "any report within the
    /// window" — otherwise a genuine user-driven scroll to a block we never
    /// asked for, arriving shortly after an unrelated echo, would be wrongly
    /// swallowed too.
    @Test func genuineScrollToNeverRequestedBlockIsNotSuppressedByWindow() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20, 2: 30]
        )

        controller.editorDidScroll(toLine: 3) // -> block 1
        controller.targetPreviewFraction = nil
        controller.previewContentOffsetDidChange(10) // echo of block 1, swallowed
        #expect(controller.targetSourceLine == nil)

        // A genuine user scroll of the preview to block 2 — never requested
        // by us — arrives immediately after, well inside the window.
        controller.previewContentOffsetDidChange(30)

        #expect(
            controller.targetSourceLine == 5,
            "A scroll to a never-requested block must not be suppressed just because it landed inside the window"
        )
    }
}
