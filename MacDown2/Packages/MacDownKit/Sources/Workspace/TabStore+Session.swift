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
                documentRecoveryEpoch: tab.document.recoveryEpoch,
                isPinned: tab.isPinned,
                cursorPosition: nil,
                selectionLength: nil,
                scrollOffset: nil,
                previewLayout: tab.previewLayout,
                previewMode: tab.previewMode,
                encoding: tab.document.encoding,
                folderRootBookmark: tab.folderRootBookmark,
                folderRootAlias: tab.folderRootAlias
            )
        }
        return WorkspaceSession(tabs: records, activeTabID: activeTabID)
    }

    func restoreTab(from record: TabRecord) async -> WorkspaceTab? {
        if let fileURL = record.fileURL {
            return await restoreFileTab(from: record, fileURL: fileURL)
        } else if let untitledID = record.untitledDocumentID {
            guard let recovered = try? await recoveryBuffer.load(
                for: untitledID,
                epoch: record.documentRecoveryEpoch
            ) else { return nil }
            var document = FileDocument(
                text: "",
                encoding: record.encoding ?? .utf8Default,
                recoveryBuffer: recoveryBuffer,
                documentID: untitledID,
                recoveryEpoch: record.documentRecoveryEpoch
            )
            document = document.updatingText(recovered)
            return WorkspaceTab(
                id: record.id,
                document: document,
                isPinned: record.isPinned,
                cursorPosition: record.cursorPosition,
                selectionLength: record.selectionLength,
                scrollOffset: record.scrollOffset,
                previewLayout: record.previewLayout,
                previewMode: record.previewMode,
                folderRootBookmark: record.folderRootBookmark,
                folderRootAlias: record.folderRootAlias
            )
        }
        return nil
    }

    private func restoreFileTab(from record: TabRecord, fileURL: URL) async -> WorkspaceTab? {
        // Version-one sessions did not persist a recovery lifetime. Scan once
        // for their newest UUID/legacy record; new sessions always use the
        // exact lifetime they recorded.
        let recoveryEpoch = record.documentRecoveryEpoch
        let document = FileDocument(
            fileURL: fileURL,
            encoding: record.encoding ?? .utf8Default,
            recoveryBuffer: recoveryBuffer,
            recoveryEpoch: recoveryEpoch
        )
        do {
            var loaded = try await Task.detached(priority: .utility) {
                try document.load()
            }.value
            let recovered = try? await recoveryBuffer.load(for: loaded.id, epoch: recoveryEpoch)
            if let recovered, recovered != loaded.text {
                loaded = loaded.updatingText(recovered)
            } else if recovered != nil {
                // A stale copy identical to disk is not recovery state. Remove
                // it during restore so a later crash cannot revive clean text.
                await recoveryBuffer.remove(for: loaded.id, epoch: recoveryEpoch)
            }
            return tab(from: record, document: loaded)
        } catch let error as FileStoreError {
            guard let recovered = try? await recoveryBuffer.load(
                for: fileURL.absoluteString,
                epoch: recoveryEpoch
            ) else { return nil }
            let unavailable = document
                .updatingText(recovered)
                .markingBackingUnavailable(backingIssue(for: error))
            return tab(from: record, document: unavailable)
        } catch {
            return nil
        }
    }

    private func backingIssue(for error: FileStoreError) -> FileBackingIssue {
        switch error {
        case .fileMissing: .missingOrMoved
        case .permissionDenied: .permissionDenied
        case .notRegularFile: .notRegularFile
        case .readFailed, .writeFailed, .invalidURL, .encodingDetectionFailed, .fileChangedDuringRead,
             .decodingFailed, .conditionalPublicationRecoveryRequired:
            .readFailed(String(describing: error))
        }
    }

    private func tab(from record: TabRecord, document: FileDocument) -> WorkspaceTab {
        WorkspaceTab(
            id: record.id,
            document: document,
            isPinned: record.isPinned,
            cursorPosition: record.cursorPosition,
            selectionLength: record.selectionLength,
            scrollOffset: record.scrollOffset,
            previewLayout: record.previewLayout,
            previewMode: record.previewMode,
            folderRootBookmark: record.folderRootBookmark,
            folderRootAlias: record.folderRootAlias
        )
    }
}
