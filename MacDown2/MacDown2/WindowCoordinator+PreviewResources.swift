import AppKit
import FileCore
import Workspace

extension WindowCoordinator {
    /// The request originates in a document view, so use that view's native window rather than ambient key focus.
    func allowPreviewResources(for model: WorkspaceModel, document: FileDocument, tabID: UUID) {
        guard let controller = controllers.first(where: { $0.model === model }),
              controller.model.tabStore.activeTabID == tabID,
              let current = controller.model.activeDocument,
              current.id == document.id,
              current.recoveryEpoch == document.recoveryEpoch,
              current.fileURL == document.fileURL
        else { return }
        controller.choosePreviewResourceFolder(for: current)
    }
}

extension WindowController {
    func choosePreviewResourceFolder(for document: FileDocument) {
        guard !isClosed, let window, let documentURL = document.fileURL,
              let origin = previewResourceState.beginSelection(for: document)
        else { return }

        Task { @MainActor [weak self] in
            let provider = NSFilePanelProvider(window: window)
            guard let selection = await provider.choosePreviewResourceFolder(near: documentURL) else {
                self?.previewResourceState.cancelSelection(origin)
                return
            }
            guard let self else { return }
            do {
                try await previewResourceState.install(selection, from: origin) { [weak self] in
                    self?.model.activeDocument
                }
            } catch {
                let current = model.activeDocument
                let shouldPresentError = current.map {
                    previewResourceState.isPendingSelection(origin, for: $0)
                } == true
                previewResourceState.cancelSelection(origin)
                guard shouldPresentError else { return }
                if case PreviewResourceAdmissionError.revoked = error {
                    return
                }
                let alert = NSAlert()
                alert.messageText = String(localized: "Preview resources unavailable")
                if case PreviewResourceSelectionError.folderDoesNotContainDocument = error {
                    alert.informativeText = String(localized: "Choose a folder containing this document's folder.")
                } else {
                    alert
                        .informativeText = String(localized: "The selected folder could not be used. Please try again.")
                }
                alert.beginSheetModal(for: window) { _ in }
            }
        }
    }
}
