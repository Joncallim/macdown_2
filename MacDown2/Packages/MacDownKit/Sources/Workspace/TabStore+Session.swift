import FileCore
import Foundation

extension TabStore {
    /// Returns the session representation for this store's tabs.
    ///
    /// Note: cursor position, selection length, and scroll offset are transient
    /// editor state owned by the live `EditorTextSystem`. The app target writes
    /// those values via `WindowCoordinator.saveSession()` after reading them from
    /// `EditorTextSystemStore`; this method intentionally leaves them `nil`
    /// because `TabStore` does not have access to the live text systems.
    func currentSession() -> WorkspaceSession {
        let records = tabs.map { tab in
            TabRecord(
                id: tab.id,
                fileURL: tab.document.fileURL,
                untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                isPinned: tab.isPinned,
                cursorPosition: nil,
                selectionLength: nil,
                scrollOffset: nil
            )
        }
        return WorkspaceSession(tabs: records, activeTabID: activeTabID)
    }

    func restoreTab(from record: TabRecord) async -> WorkspaceTab? {
        if let fileURL = record.fileURL {
            let document = FileDocument(fileURL: fileURL, recoveryBuffer: recoveryBuffer)
            do {
                var loaded = try document.load()
                let recovered = try? await recoveryBuffer.load(for: loaded.id)
                if let recovered, recovered != loaded.text {
                    loaded = loaded.updatingText(recovered)
                }
                return WorkspaceTab(
                    id: record.id,
                    document: loaded,
                    isPinned: record.isPinned,
                    cursorPosition: record.cursorPosition,
                    selectionLength: record.selectionLength,
                    scrollOffset: record.scrollOffset
                )
            } catch {
                return nil
            }
        } else if let untitledID = record.untitledDocumentID {
            guard let recovered = try? await recoveryBuffer.load(for: untitledID) else { return nil }
            var document = FileDocument(text: "", recoveryBuffer: recoveryBuffer)
            document = document.updatingText(recovered)
            return WorkspaceTab(
                id: record.id,
                document: document,
                isPinned: record.isPinned,
                cursorPosition: record.cursorPosition,
                selectionLength: record.selectionLength,
                scrollOffset: record.scrollOffset
            )
        }
        return nil
    }
}
