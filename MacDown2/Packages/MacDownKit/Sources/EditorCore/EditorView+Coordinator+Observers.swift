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
    }
}
