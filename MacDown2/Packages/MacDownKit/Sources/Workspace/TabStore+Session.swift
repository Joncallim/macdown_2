import FileCore
import Foundation

extension TabStore {
    func currentSession() -> WorkspaceSession {
        let records = tabs.map { tab in
            TabRecord(
                id: tab.id,
                fileURL: tab.document.fileURL,
                untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                isPinned: tab.isPinned,
                cursorPosition: nil,
                scrollOffset: nil
            )
        }
        return WorkspaceSession(tabs: records, activeTabID: activeTabID)
    }

    func restoreTab(from record: TabRecord) async -> WorkspaceTab? {
        if let fileURL = record.fileURL {
            let document = FileDocument(fileURL: fileURL)
            do {
                var loaded = try document.load()
                let recovered = try? await RecoveryBuffer.shared.load(for: loaded.id)
                if let recovered, recovered != loaded.text {
                    loaded = loaded.updatingText(recovered)
                }
                return WorkspaceTab(id: record.id, document: loaded, isPinned: record.isPinned)
            } catch {
                return nil
            }
        } else if let untitledID = record.untitledDocumentID {
            guard let recovered = try? await RecoveryBuffer.shared.load(for: untitledID) else { return nil }
            var document = FileDocument(text: "")
            document = document.updatingText(recovered)
            return WorkspaceTab(id: record.id, document: document, isPinned: record.isPinned)
        }
        return nil
    }
}
