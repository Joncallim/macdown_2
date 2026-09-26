import AppKit

// MARK: - Content (whole-document replacement)

public extension EditorTextSystem {
    /// Replaces the entire document text. This is intended for external reloads
    /// and conflict resolution; it resets selection and scroll.
    func setText(_ text: String) {
        textView.string = text
        editRevision &+= 1
        lineIndex.rebuild(text: text as NSString)
        // A wholesale text replacement invalidates any measured height from
        // the previous document — see `syncFrameHeightToContent`. It also
        // invalidates any cached multi-selection state (§6.10, Slice 3b-i):
        // a stale `storedSelectionSet` referencing offsets from the
        // PREVIOUS document could otherwise be wrongly resurrected by
        // `selectionSet`'s getter if the new document's own caret happens
        // to coincide with the old cached primary (e.g. both `(0, 0)`) —
        // found by an independent hostile review of PR #129.
        measuredContentHeight = 0
        lastFrameSyncSignature = nil
        storedSelectionSet = nil
    }

    /// Captures the selection and vertical viewport before an external reload.
    func viewportSnapshot() -> EditorViewportSnapshot {
        EditorViewportSnapshot(selectedRange: selectedRange, scrollOffset: scrollOffset)
    }

    /// Replaces editor content from a stable external snapshot without
    /// creating a user edit or losing the visible location where possible.
    func replaceTextFromExternal(
        _ text: String,
        preserving snapshot: EditorViewportSnapshot,
        clearUndo: Bool
    ) {
        isPerformingProgrammaticTextUpdate = true
        defer { isPerformingProgrammaticTextUpdate = false }

        textView.string = text
        editRevision &+= 1
        lineIndex.rebuild(text: text as NSString)
        measuredContentHeight = 0
        lastFrameSyncSignature = nil
        // See `setText`'s identical reset for why: a stale multi-selection
        // cache must never survive a whole-document replacement.
        storedSelectionSet = nil
        textView.setSelectedRange(clampedToLiveText(snapshot.selectedRange))
        pendingScrollOffset = max(0, snapshot.scrollOffset)
        if clearUndo {
            undoManager.removeAllActions()
        }
        scheduleFrameHeightSync()
    }
}
