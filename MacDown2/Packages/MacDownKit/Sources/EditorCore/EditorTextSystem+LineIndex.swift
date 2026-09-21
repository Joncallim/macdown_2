import AppKit

extension EditorTextSystem {
    /// Called once per atomic edit this text system observes — including
    /// once per individual range inside an `EditorEditTransaction`,
    /// independent of that transaction's own SwiftUI-publication
    /// suppression (`isApplyingMultiRangeTransaction`), since the line
    /// index must stay correct for every intermediate state, not just the
    /// transaction's final one.
    ///
    /// `editedRange` is in *pre-edit* coordinates. `newText` is read
    /// directly from the live text view (`text`), which by the time this
    /// is called already reflects the edit — an O(1) reference read, not a
    /// copy. This must never be called with a `newText` synthesized via
    /// `NSString.replacingCharacters(in:with:)` before the edit happens,
    /// which would cost an O(document length) copy per keystroke and
    /// defeat the incremental index's entire purpose.
    func noteIncrementalEdit(editedRange: NSRange, replacementUTF16Length: Int) {
        lineIndex.applying(
            editedRange: editedRange,
            replacementUTF16Length: replacementUTF16Length,
            newText: text as NSString
        )
    }

    /// Full rebuild for edit paths that bypass the incremental hook above
    /// entirely — currently just undo/redo (see `registerUndoRedoObservers()`
    /// below). Undo/redo are comparatively rare next to every-keystroke
    /// edits, so an O(n) rebuild here is an acceptable, simple trade
    /// against chasing a lower-level storage-delegate hook.
    func rebuildLineIndex() {
        lineIndex.rebuild(text: text as NSString)
    }

    /// Undo/redo replays a previously-approved edit directly against the
    /// text storage — it does NOT go through
    /// `NSTextViewDelegate.shouldChangeTextIn:replacementString:`/
    /// `textDidChange`, verified empirically
    /// (`EditorLineIndexWiringTests.undoAndRedoKeepLineIndexCorrect` failed
    /// without this: `text` correctly reverted via `NSTextView`'s own undo
    /// machinery, but `lineIndex` was never told about it at all).
    ///
    /// Registered on `EditorTextSystem` itself rather than on the SwiftUI
    /// `EditorView` layer, so this invariant holds for every consumer of
    /// this class — including tests that mount a bare `EditorTextSystem`
    /// without going through `EditorView.makeNSView` at all (an earlier
    /// version of this fix lived there, and a test using the lighter
    /// `EditingAssistIntegrationSupport.makeCoordinator` helper — which
    /// several other suites already relied on — proved it never ran).
    ///
    /// Deliberately does NOT capture `undoManager` once here and register
    /// against that fixed object: `undoManager` (`textView.undoManager ??
    /// fallbackUndoManager`) resolves to `fallbackUndoManager` at `init`
    /// time, since `NSTextView.undoManager` needs a real window to return
    /// its own — but once this text view IS installed in a window (as
    /// production always does, immediately after `init`), `textView.undoManager`
    /// switches to the WINDOW's own `NSUndoManager`, a different instance
    /// than whatever was captured earlier. An observer registered against
    /// the stale, no-longer-used `fallbackUndoManager` would never fire —
    /// exactly the failure this second version fixes, caught by the same
    /// test failing even after the observer moved to this class. Observing
    /// with `object: nil` (any sender) and re-resolving `self.undoManager`
    /// fresh inside the handler is correct regardless of when that identity
    /// changes, and the equality check discards notifications from any
    /// OTHER text system's undo manager (`NotificationCenter.default` is
    /// process-wide, not scoped to one instance).
    func registerUndoRedoObservers() {
        undoRedoObservers = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                // Extracted as `ObjectIdentifier` -- a plain, `Sendable`
                // value wrapping just the pointer identity -- rather than
                // keeping a reference to `notification.object` itself
                // (typed `Any?`) or to `notification` as a whole (neither
                // `Notification` nor Foundation's `UndoManager` is
                // `Sendable`). Swift's strict concurrency checking flags
                // passing either non-Sendable value into the
                // `assumeIsolated` closure below as a data-race risk, even
                // though this closure only ever runs on the main thread in
                // practice.
                let senderIdentity = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                // `queue: nil` invokes this synchronously on the posting
                // thread, and AppKit's `UndoManager` always posts these on
                // the main thread — runtime-guaranteed but not statically
                // provable to the compiler, hence `assumeIsolated` rather
                // than a `Task { @MainActor in ... }` hop (which would
                // defer the rebuild to a later runloop turn instead of
                // keeping it synchronous with the undo/redo it reacts to).
                MainActor.assumeIsolated {
                    guard let self, senderIdentity == ObjectIdentifier(self.undoManager) else { return }
                    self.rebuildLineIndex()
                }
            }
        }
    }
}
