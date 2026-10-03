import AppKit
import FileCore
import Foundation

extension WindowCoordinator {
    /// Opens `url`, or activates the window that already shows it. Opens of the SAME file are
    /// serialised (`KeyedSerialRunner`), so a second request waits for the first and then finds
    /// its window instead of creating a duplicate document.
    func openDocument(
        at url: URL,
        folderRoot: URL? = nil,
        folderAccessURL: URL? = nil,
        folderSelectionURL: URL? = nil,
        folderRenameURL: URL? = nil,
        relativeTo overrideKeyWindow: NSWindow? = nil,
        encoding: FileEncodingMetadata? = nil
    ) async {
        let resolved = url.resolvingFinalSymlink()
        await documentOpens.run(key: resolved.standardizedFileURL) { [self] in
            await performOpenDocument(
                at: resolved,
                folderRoot: folderRoot,
                folderAccessURL: folderAccessURL,
                folderSelectionURL: folderSelectionURL,
                folderRenameURL: folderRenameURL,
                relativeTo: overrideKeyWindow,
                encoding: encoding
            )
        }
    }
}
