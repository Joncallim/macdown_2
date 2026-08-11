import AppKit
import EditorCore
import FileCore
import FileTree
import Foundation
import Workspace

enum TerminationRecoveryPresentation {
    static let title = "Recovery Could Not Be Secured"
    static let message = "MacDown kept this window open because unsaved recovery data could not be verified. "
        + "Retry, or use Save As to preserve your changes."
    static let retryTitle = "Retry"
    static let saveAsTitle = "Save As…"
}

enum SessionSaveResult {
    case saved
    case recoveryFailed(WindowController)
    case sessionPublicationFailed
    /// Cleanup work is intentionally not serialized independently of the
    /// live document. Termination is blocked until its exact retry action has
    /// completed, so a relaunch cannot forget the action and retire the wrong
    /// lifetime.
    case pendingRecoveryCleanup(WindowController)

    var persisted: Bool {
        if case .saved = self {
            return true
        }
        return false
    }
}

private struct ControllerTabSnapshot {
    let controller: WindowController
    let tab: TabSnapshot
}

extension WindowCoordinator {
    /// Saves the current set of open documents as the session. Dirty documents
    /// are snapshotted before any `await` so recovery and session JSON remain
    /// consistent even while the main actor handles later user edits.
    @discardableResult
    func saveSession() async -> Bool {
        await saveSessionResult().persisted
    }

    func saveSessionResult(
        allowingSaveAsPublicationFor publishingModel: WorkspaceModel? = nil
    ) async -> SessionSaveResult {
        if let pendingController = controllers.first(where: {
            $0.model.hasPendingRecoveryCleanup && $0.model !== publishingModel
        }) {
            return .pendingRecoveryCleanup(pendingController)
        }
        let (snapshot, activeID) = sessionSnapshot()
        if let failedController = await persistDirtyRecovery(in: snapshot) {
            return .recoveryFailed(failedController)
        }
        let session = WorkspaceSession(tabs: snapshot.map(\.tab.record), activeTabID: activeID)
        guard sessionStore.saveSessionVerified(session) else {
            if let controller = controllers.first {
                return .recoveryFailed(controller)
            }
            return .sessionPublicationFailed
        }
        return .saved
    }

    private func sessionSnapshot() -> ([ControllerTabSnapshot], UUID?) {
        let snapshot = controllers.compactMap { controller -> ControllerTabSnapshot? in
            guard let tab = controller.model.tabStore.tabs.first else { return nil }
            let system = controller.editorStore.existingSystem(for: tab.id.uuidString)
            let selectedRange = system?.selectedRange
            let lexicalRoot = controller.model.folderURL
            let physicalRoot = lexicalRoot?.resolvingSymlinksInPath().standardizedFileURL
            let scope = physicalRoot.map(FolderAccessScope.init)
            let bookmark = physicalRoot.flatMap { try? $0.bookmarkData(options: .withSecurityScope) }
                ?? tab.folderRootBookmark
            _ = scope
            return ControllerTabSnapshot(
                controller: controller,
                tab: TabSnapshot(
                    record: TabRecord(
                        id: tab.id,
                        fileURL: tab.document.fileURL,
                        untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                        documentRecoveryEpoch: tab.document.recoveryEpoch,
                        isPinned: tab.isPinned,
                        cursorPosition: selectedRange?.location,
                        selectionLength: selectedRange?.length,
                        scrollOffset: system.map { Double($0.scrollOffset) },
                        previewLayout: tab.previewLayout,
                        folderRootBookmark: bookmark,
                        folderRootAlias: lexicalRoot ?? tab.folderRootAlias
                    ),
                    documentID: tab.document.id,
                    documentText: tab.document.text,
                    documentState: tab.document.state,
                    documentGeneration: tab.document.mutationGeneration,
                    documentRecoveryEpoch: tab.document.recoveryEpoch
                )
            )
        }
        let activeID = controllers.first { $0.window?.isKeyWindow ?? false }?.model.tabStore.activeTabID
        return (snapshot, activeID)
    }

    private func persistDirtyRecovery(in snapshot: [ControllerTabSnapshot]) async -> WindowController? {
        for entry in snapshot where entry.tab.documentState == .dirty || entry.tab.documentState == .conflict {
            do {
                let persisted = try await recoveryBuffer.saveCurrentLifetime(
                    content: entry.tab.documentText,
                    for: entry.tab.documentID,
                    version: entry.tab.documentGeneration,
                    epoch: entry.tab.documentRecoveryEpoch
                )
                guard persisted else { return entry.controller }
            } catch {
                return entry.controller
            }
        }
        return nil
    }

    /// Explicit UI seam for a rejected termination snapshot. The application
    /// remains running; the user can retry after a transient failure or choose
    /// Save As from the affected document window.
    func presentTerminationRecoveryRequired(for target: WindowController? = nil) {
        terminationRecoveryState = .recoveryRequired
        terminationRecoveryController = target
        guard let window = target?.window
            ?? controllers.first(where: { $0.window?.isKeyWindow == true })?.window
            ?? controllers.first?.window
        else { return }
        let alert = NSAlert()
        alert.messageText = TerminationRecoveryPresentation.title
        alert.informativeText = TerminationRecoveryPresentation.message
        alert.alertStyle = .critical
        alert.addButton(withTitle: TerminationRecoveryPresentation.retryTitle)
        alert.addButton(withTitle: TerminationRecoveryPresentation.saveAsTitle)
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    let retryTarget = target ?? terminationRecoveryController
                    await retryTarget?.model.retryRecoveryCleanup()
                    switch await saveSessionResult() {
                    case .saved:
                        terminationRecoveryState = .none
                        NSApp.terminate(nil)
                    case let .recoveryFailed(controller), let .pendingRecoveryCleanup(controller):
                        presentTerminationRecoveryRequired(for: controller)
                    case .sessionPublicationFailed:
                        presentTerminationRecoveryRequired()
                    }
                } else {
                    if let target {
                        await target.saveDocumentAs()
                    } else {
                        await controllers.first(where: { $0.window === window })?.saveDocumentAs()
                    }
                }
            }
        }
    }

    func handleTerminationSessionResult(_ persisted: Bool) -> Bool {
        guard !persisted else {
            terminationRecoveryState = .none
            terminationRecoveryController = nil
            return true
        }
        presentTerminationRecoveryRequired()
        return false
    }

    func handleTerminationSessionResult(_ result: SessionSaveResult) -> Bool {
        let controller: WindowController
        switch result {
        case .saved:
            terminationRecoveryState = .none
            terminationRecoveryController = nil
            return true
        case let .recoveryFailed(failedController), let .pendingRecoveryCleanup(failedController):
            controller = failedController
        case .sessionPublicationFailed:
            presentTerminationRecoveryRequired()
            return false
        }
        presentTerminationRecoveryRequired(for: controller)
        return false
    }

    /// Applies a workspace-owned preview layout to the key document.
    func setPreviewLayout(_ layout: PreviewLayoutMode) {
        guard let keyModel,
              let activeTabID = keyModel.tabStore.activeTabID
        else { return }
        keyModel.tabStore.setPreviewLayout(layout, for: activeTabID)
        scheduleSaveSession()
    }
}
