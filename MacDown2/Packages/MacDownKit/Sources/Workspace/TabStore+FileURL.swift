import FileCore
import Foundation

public extension TabStore {
    /// Returns the tab for a standardized file URL, if open.
    func tabID(forFileURL url: URL) -> UUID? {
        tabs.first { tab in
            tab.document.fileURL.map { PhysicalFileIdentity.matches($0, url) } ?? false
        }?.id
    }

    /// Applies an in-app move/rename to an open document. External watcher
    /// events deliberately do not call this; that is E18 territory.
    func documentWasRenamed(from old: URL, to new: URL) {
        let oldRoot = old.standardizedFileURL
        let newRoot = new.standardizedFileURL
        var changed = false
        for index in tabs.indices {
            guard let fileURL = tabs[index].document.fileURL?.standardizedFileURL,
                  let remapped = remappedFileURL(fileURL, from: oldRoot, to: newRoot)
            else { continue }
            let document = tabs[index].document
            let oldID = document.id
            tabs[index].document = document.renamed(to: remapped)
            if document.state != .clean {
                let recoveryBuffer = document.recoveryBuffer
                let newID = tabs[index].document.id
                Task { await recoveryBuffer.migrate(from: oldID, to: newID) }
            }
            changed = true
        }
        if changed {
            persist()
        }
    }

    /// Returns the UI intent for a sidebar deletion. Dirty documents remain
    /// open for the app target's Save As / discard / keep-open sheet.
    func documentFileWasDeleted(at url: URL) -> DeletedDocumentOutcome {
        let deletedRoot = url.standardizedFileURL
        guard let index = tabs.firstIndex(where: { tab in
            guard let fileURL = tab.document.fileURL?.standardizedFileURL else { return false }
            return PhysicalFileIdentity.matches(fileURL, deletedRoot)
                || fileURL.pathComponents.starts(with: deletedRoot.pathComponents)
        }) else { return .notOpen }
        let id = tabs[index].id
        if tabs[index].document.state == .clean {
            removeTab(at: index)
            persist()
            return .closedCleanTab(id)
        }
        return .needsPrompt(id)
    }

    private func remappedFileURL(_ url: URL, from old: URL, to new: URL) -> URL? {
        if PhysicalFileIdentity.matches(url, old) {
            return new.standardizedFileURL
        }
        let components = url.pathComponents
        guard components.starts(with: old.pathComponents) else { return nil }
        let suffix = components.dropFirst(old.pathComponents.count).joined(separator: "/")
        if suffix.isEmpty {
            return new.standardizedFileURL
        }
        return new.appendingPathComponent(suffix, isDirectory: false).standardizedFileURL
    }
}
