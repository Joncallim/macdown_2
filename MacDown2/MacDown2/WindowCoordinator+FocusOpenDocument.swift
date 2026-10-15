import AppKit
import FileCore
import Foundation

struct FolderOpenContext {
    let root: URL?
    let accessURL: URL?
    let selectionURL: URL?
    let renameURL: URL?
}

extension WindowCoordinator {
    /// Opening a file that is already open focuses its window. When a specific
    /// encoding was asked for, the document is re-read with it through the
    /// window's own reopen path, which guards unsaved changes.
    func focus(
        _ existing: WindowController,
        for url: URL,
        folder: FolderOpenContext,
        encoding: FileEncodingMetadata?,
        shouldContinue: (@MainActor () -> Bool)? = nil
    ) async {
        guard let window = existing.window else { return }
        guard shouldContinue?() ?? true else { return }
        if let root = folder.root, existing.fileTreeModel.root == nil {
            guard shouldContinue?() ?? true else { return }
            existing.model.setFolderRoot(root)
            await existing.setFileTreeRoot(root, accessURL: folder.accessURL)
            guard shouldContinue?() ?? true else { return }
        }
        existing.fileTreeModel.selectedURL = folder.selectionURL
        existing.fileTreeModel.renamingURL = folder.renameURL
        guard shouldContinue?() ?? true else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        recentFileDocuments.record(url)
        if let encoding {
            await existing.reopenDocument(withEncoding: encoding.encoding)
        }
    }
}
