import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 2a — proves `EditorTextSystem.lineIndex` stays correct
/// across every real, AppKit-driven edit path, not just the pure
/// `EditorLineIndex.applying(...)` unit tests. Each test compares the
/// system's live (incrementally updated) index against a fresh full
/// rebuild of the resulting text -- the same equivalence style
/// `EditorLineIndexTests.assertIncrementalMatchesRebuild` uses, but driven
/// through real `NSTextView` editing rather than calling `applying`
/// directly, so a wiring mistake here (e.g. missing a delegate hook, or a
/// stale `pendingLineIndexEdit`) is caught even if the pure type itself is
/// correct.
@MainActor
@Suite("EditorLineIndex wiring")
struct EditorLineIndexWiringTests {
    private let support = EditingAssistIntegrationSupport.self

    private func assertMatchesFreshRebuild(
        _ system: EditorTextSystem,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rebuilt = EditorLineIndex(text: system.text as NSString)
        #expect(
            system.lineIndex == rebuilt,
            "system.lineIndex diverged from a fresh rebuild",
            sourceLocation: sourceLocation
        )
    }

    @Test func initialLineIndexMatchesInitialText() {
        let system = support.makeSystem(text: "line1\nline2\nline3")
        assertMatchesFreshRebuild(system)
    }

    @Test func plainTypingUpdatesLineIndexIncrementally() {
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // Simulates real typed input: AppKit's own insertText(_:) path,
        // which triggers shouldChangeTextIn/textDidChange exactly as a
        // genuine keystroke would.
        system.textView.setSelectedRange(NSRange(location: 5, length: 0))
        system.textView.insertText("\n-- inserted --\n", replacementRange: NSRange(location: 5, length: 0))

        assertMatchesFreshRebuild(system)
    }

    @Test func multipleSequentialEditsKeepLineIndexCorrect() {
        let system = support.makeSystem(text: "a\nb\nc")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.insertText("\nnew", replacementRange: NSRange(location: 1, length: 0))
        assertMatchesFreshRebuild(system)

        system.textView.insertText("start\n", replacementRange: NSRange(location: 0, length: 0))
        assertMatchesFreshRebuild(system)

        system.textView.insertText("\r\n", replacementRange: NSRange(location: system.text.utf16.count, length: 0))
        assertMatchesFreshRebuild(system)
    }

    @Test func multiRangeTransactionUpdatesLineIndexForEveryRange() {
        let system = support.makeSystem(text: "cat\ncat\ncat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.apply(EditorEditTransaction(replacements: [
            TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog\ndog"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog\ndog"),
        ]))

        assertMatchesFreshRebuild(system)
    }

    @Test func assistInterceptedEditUpdatesLineIndexToTheAssistsActualEdit() {
        // A Markdown command (E10's `performMarkdownCommand`) intercepts and
        // replaces via `applyAssistOutcome`'s nested `insertText` call --
        // never through the "outer" shouldChangeTextIn path at all, since
        // this isn't triggered by typing. Proves the line index reflects
        // the assist's real edit, not a stale/uncaptured state.
        let system = support.makeMarkdownSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.setSelectedRange(NSRange(location: 0, length: 5))
        _ = system.performMarkdownCommand(.bold)

        assertMatchesFreshRebuild(system)
    }

    @Test func undoAndRedoKeepLineIndexCorrect() {
        let system = support.makeSystem(text: "one\ntwo\nthree")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.insertText(
            "\nfour\nfive",
            replacementRange: NSRange(location: system.text.utf16.count, length: 0)
        )
        assertMatchesFreshRebuild(system)

        system.undoManager.undo()
        assertMatchesFreshRebuild(system)

        system.undoManager.redo()
        assertMatchesFreshRebuild(system)
    }

    @Test func setTextRebuildsLineIndex() {
        let system = support.makeSystem(text: "a\nb")
        system.setText("x\ny\nz\nw")
        assertMatchesFreshRebuild(system)
    }

    @Test func replaceTextFromExternalRebuildsLineIndex() {
        let system = support.makeSystem(text: "a\nb\nc")
        let snapshot = system.viewportSnapshot()
        system.replaceTextFromExternal("x\ny", preserving: snapshot, clearUndo: true)
        assertMatchesFreshRebuild(system)
    }

    @Test func editWithoutACoordinatorDoesNotCrashButLeavesTheIndexUnwired() {
        // Documents the honest limitation: the incremental hook lives in
        // `EditorView.Coordinator` (production always attaches one via
        // `EditorView.makeNSView`); without one, `shouldChangeTextIn`/
        // `textDidChange` never fire at all (no delegate to call), so the
        // index is never told about the edit. Not a bug -- `setText`/
        // `replaceTextFromExternal` are always available as an explicit
        // full-rebuild escape hatch -- but worth pinning so a future
        // refactor that moves this hook doesn't silently assume otherwise.
        let system = support.makeSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.textView.insertText(" world", replacementRange: NSRange(location: 5, length: 0))

        #expect(system.text == "hello world")
        #expect(system.lineIndex != EditorLineIndex(text: system.text as NSString))
    }
}
