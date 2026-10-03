import AppKit

// MARK: - Scroll/undo NotificationCenter observers

// Extracted from `EditorView.swift` to keep that file under its line-count
// limit, mirroring the established per-feature extension-file precedent.

extension EditorView.Coordinator {
    @objc @MainActor func scrollViewDidScroll(_: Notification) {
        guard let system else { return }
        onScrollChange?(system.topVisibleUTF16Offset)
    }

    /// `EditorTextSystem` itself keeps `lineIndex` correct across undo/redo
    /// (see its own `registerUndoRedoObservers()`); this coordinator-level
    /// observer exists only to redraw the gutter, which `EditorTextSystem`
    /// has no reference to.
    @objc @MainActor func undoManagerDidChange(_ notification: Notification) {
        // Registered with `object: nil` (see `registerCoordinatorObservers`'s
        // doc comment), so this fires for every text system's undo/redo in
        // the app — filter to this one's current (freshly-resolved, not
        // cached) undo manager.
        guard let system, notification.object as AnyObject === system.undoManager else { return }
        gutterView?.updateThickness()
        publishTextAfterUndoRedo(of: system)
    }

    /// TextKit 2 applies an undo/redo without posting `NSText.didChangeNotification`, so
    /// `textDidChange` never ran: the binding (and with it the document model, Save, Preview,
    /// the outline and the recovery buffer) kept the pre-undo text — and the next `updateNSView`
    /// pushed that stale text back into the view, silently redoing the undo.
    @MainActor private func publishTextAfterUndoRedo(of system: EditorTextSystem) {
        guard !isApplyingModelText,
              !system.isPerformingProgrammaticTextUpdate,
              !system.isApplyingMultiRangeTransaction
        else { return }
        isApplyingModelText = true
        textBinding?.wrappedValue = system.text
        isApplyingModelText = false
        system.noteTextEdit()
        system.scheduleFrameHeightSync()
    }
}
