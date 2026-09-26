import AppKit

// MARK: - Escape-collapse (EPIC-22 §6.9, Slice 3a)

//
// Extracted from `EditorView.swift` to keep that file under its line-count
// limit, mirroring the established `DocumentEditorSplitView+EditorPane.swift`
// precedent (Slice 2b) for splitting an extension out once a file grows.

extension EditorView.Coordinator {
    /// Escape (`cancelOperation:`, called from `doCommandBy(_:)`): collapses
    /// to the primary selection and consumes the key event. Returns `false`
    /// (falls through to AppKit's default handling of Escape, e.g.
    /// dismissing a completion panel if one is ever added) when the
    /// selection is already single, so this never shadows Escape's other
    /// native behaviors — it only ever intercepts the multi-selection case.
    @MainActor
    func collapseMultipleSelectionsIfNeeded(system: EditorTextSystem) -> Bool {
        var selection = system.selectionSet
        guard selection.isMultiple else { return false }
        selection.collapseToPrimary()
        system.selectionSet = selection
        return true
    }
}
