import AppKit
import TextSearch

/// Opens a folder-search result and reveals the matched range (EPIC-22
/// §6.16, Slice 7b) — reuses the existing document-open path
/// (`openDocument(at:folderRoot:...)`, the same one Quick Open and the
/// file tree already route through) rather than inventing a third opening
/// mechanism, per §6.15's own precedent.
extension WindowCoordinator {
    /// `range` is the first match's own UTF-16 range in `relativePath`'s
    /// text, as read at search time. If the file is already open and has
    /// been edited since, the live buffer may no longer agree with that
    /// range — `revealSelection` clamps against the live text length
    /// (`EditorTextSystem`'s own existing behavior, shared with Go to
    /// Line), so a now-stale range degrades to "select somewhere near the
    /// end" rather than crashing or silently doing nothing; a precise
    /// re-search-on-open is Slice 7c/polish scope, not required for a
    /// correct (if occasionally imprecise) result here.
    func openFolderSearchResult(
        relativePath: String,
        root: URL,
        folderAccessURL: URL?,
        range: NSRange
    ) async {
        let url = root.appendingPathComponent(relativePath)
        await openDocument(at: url, folderRoot: root, folderAccessURL: folderAccessURL, folderSelectionURL: url)
        guard let controller = controllerForDocument(url: url),
              let tabID = controller.model.tabStore.tabID(forFileURL: url)
        else { return }

        // `WindowController.init` eagerly creates the ACTIVE tab's
        // `EditorTextSystem` synchronously (`makeSessionsForActiveTab()`),
        // so for a document that was not already open anywhere --
        // `openDocument` opens it into a brand-new window and makes it the
        // active tab -- `existingSystem` already succeeds on the very first
        // try. The real gap this retry protects is `openDocument`'s OTHER
        // branch: a document that is already open, but as a background
        // (non-active) tab in an existing window, is brought to the front
        // as a WINDOW without necessarily being switched to as the active
        // TAB within it, and a non-active tab's own `EditorTextSystem` may
        // not exist yet (`DocumentEditorSplitView`'s panes create their
        // `EditorView`, and so their system, lazily as they mount). An
        // independent review of this slice found the ORIGINAL version of
        // this comment's own justification did not hold for the common
        // case, but the underlying seam is still worth keeping for this
        // background-tab case; if that tab genuinely never becomes active,
        // this loop still exhausts and silently returns without revealing
        // — a disclosed, known limitation (the file's window still comes
        // forward via `openDocument` regardless), not something this
        // bounded retry can fix on its own without a deeper change to
        // `openDocument`'s own tab-activation behavior, which is shared
        // with Quick Open and out of this slice's scope.
        for _ in 0 ..< 10 {
            if let textSystem = controller.editorStore.existingSystem(for: tabID.uuidString) {
                textSystem.revealSelection(utf16Range: range, flash: true, animated: true)
                return
            }
            await Task.yield()
        }
    }
}
