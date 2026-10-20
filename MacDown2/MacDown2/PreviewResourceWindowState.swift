import FileCore
import Foundation
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var previewResourceWindowState: PreviewResourceWindowState?
}

/// One native document window owns its folder grant and all preview load tokens. A document change or window close
/// revokes token admission synchronously, before asynchronous worker-ledger cleanup begins.
@MainActor
@Observable
final class PreviewResourceWindowState {
    private struct Attachment {
        let documentID: String
        let recoveryEpoch: UUID
        let documentURL: URL
        let backing: PreviewDirectoryGrantBacking

        func matches(_ document: FileCore.FileDocument) -> Bool {
            document.id == documentID && document.recoveryEpoch == recoveryEpoch
                && document.fileURL == documentURL
        }
    }

    enum Consumer: Hashable {
        case markdown
        case html
    }

    struct SelectionOrigin: Equatable {
        let id: UUID
        let documentID: String
        let recoveryEpoch: UUID
        let documentURL: URL

        func matches(_ document: FileCore.FileDocument) -> Bool {
            document.id == documentID && document.recoveryEpoch == recoveryEpoch
                && document.fileURL == documentURL
        }
    }

    private(set) var revision = UUID()
    private var attachment: Attachment?
    private var contexts: [Consumer: PreviewResourceLoad] = [:]
    private var pendingSelection: SelectionOrigin?
    private(set) var isClosed = false

    isolated deinit {
        // WindowController calls `close()` deterministically; this also protects a future owner that is released
        // without its explicit close path. Synchronous token revocation precedes actor cleanup in either case.
        for context in contexts.values {
            context.revoke()
            Task { await PreviewResourceAdmission.shared.retire(context) }
        }
        attachment?.backing.revoke()
    }

    /// Capture the document lifetime BEFORE showing the panel. Another document, even at the same file URL, may
    /// replace it while the panel is open; that later lifetime cannot inherit this choice.
    func beginSelection(for document: FileCore.FileDocument) -> SelectionOrigin? {
        guard !isClosed, let url = document.fileURL else { return nil }
        let origin = SelectionOrigin(
            id: UUID(), documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, documentURL: url
        )
        pendingSelection = origin
        return origin
    }

    /// Called after the panel returns. Both its receipt and the document are checked against the pre-panel origin
    /// before and after opening the pinned descriptor; a stale result is revoked, never installed.
    func install(
        _ selection: PreviewResourceFolderSelection,
        from origin: SelectionOrigin,
        currentDocument: @escaping @MainActor () -> FileCore.FileDocument?
    ) async throws {
        guard !isClosed, pendingSelection == origin,
              selection.requestedDocumentURL == origin.documentURL,
              let document = currentDocument(), origin.matches(document)
        else { throw PreviewResourceAdmissionError.revoked }
        let backing = try await PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: origin.documentURL, epoch: origin.id
        )
        guard !isClosed, pendingSelection == origin,
              let current = currentDocument(), origin.matches(current)
        else {
            backing.revoke()
            throw PreviewResourceAdmissionError.revoked
        }
        revokeCurrent()
        attachment = Attachment(
            documentID: document.id, recoveryEpoch: document.recoveryEpoch,
            documentURL: selection.requestedDocumentURL, backing: backing
        )
        revision = UUID()
    }

    /// Returns a fresh immutable consumer token. Retiring one renderer cannot revoke another renderer's admitted
    /// worker, but replacing this document/window revokes both immediately.
    func beginLoad(for document: FileCore.FileDocument, consumer: Consumer) -> PreviewResourceLoad? {
        retire(consumer)
        guard !isClosed, let attachment, attachment.matches(document) else { return nil }
        let context = PreviewResourceLoad(grant: attachment.backing)
        contexts[consumer] = context
        return context
    }

    func retire(_ consumer: Consumer) {
        guard let context = contexts.removeValue(forKey: consumer) else { return }
        context.revoke()
        Task { await PreviewResourceAdmission.shared.retire(context) }
    }

    /// The controller and view lifecycle call this at document identity changes. A matching edit keeps the folder
    /// authority, while its renderer creates a new per-revision load token.
    func reconcile(with document: FileCore.FileDocument?) {
        if let pendingSelection,
           document.map({ pendingSelection.matches($0) }) != true {
            self.pendingSelection = nil
        }
        guard let attachment else { return }
        guard let document, attachment.matches(document) else { revokeCurrent(); return }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        revokeCurrent()
    }

    private func revokeCurrent() {
        pendingSelection = nil
        for consumer in Array(contexts.keys) {
            retire(consumer)
        }
        attachment?.backing.revoke()
        attachment = nil
        revision = UUID()
    }
}
