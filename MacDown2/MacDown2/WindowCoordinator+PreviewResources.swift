import AppKit
import FileCore
import Preview
import Workspace

extension WindowCoordinator {
    private var previewCommandModel: WorkspaceModel? {
        currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?.model
    }

    var canChooseKeyPreviewResources: Bool {
        _ = commandStateRevision
        guard let tab = previewCommandModel?.tabStore.activeTab else { return false }
        return DocumentEditorSplitView.resourceAccessAvailable(document: tab.document, mode: tab.previewMode)
    }

    var canSetKeyHTMLPreviewMode: Bool {
        _ = commandStateRevision
        guard let document = previewCommandModel?.activeDocument else { return false }
        return PreviewRouter.previewKind(for: document.format) == .html
    }

    func chooseKeyPreviewResources() {
        guard let model = previewCommandModel, let tab = model.tabStore.activeTab,
              DocumentEditorSplitView.resourceAccessAvailable(document: tab.document, mode: tab.previewMode)
        else { return }
        allowPreviewResources(for: model, document: tab.document, tabID: tab.id)
    }

    func setKeyHTMLPreviewMode(_ mode: PreviewMode) {
        guard let model = previewCommandModel, let tab = model.tabStore.activeTab,
              PreviewRouter.previewKind(for: tab.document.format) == .html,
              PreviewRouter.supports(mode, for: tab.document.format)
        else { return }
        model.tabStore.setPreviewMode(mode, for: tab.id)
        scheduleSaveSession()
    }

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
    private func mayPresentPreviewResourceSelection(
        _ origin: PreviewResourceWindowState.SelectionOrigin, in window: NSWindow
    ) -> Bool {
        guard !isClosed, self.window === window, let document = model.activeDocument else { return false }
        return previewResourceState.isPendingSelection(origin, for: document)
    }

    @discardableResult
    func choosePreviewResourceFolder(
        for document: FileDocument,
        chooser: @escaping @MainActor (NSWindow, URL) async -> PreviewResourceFolderSelection? = { window, url in
            await NSFilePanelProvider(window: window).choosePreviewResourceFolder(near: url)
        }
    ) -> Task<Void, Never>? {
        guard !isClosed, let window, let documentURL = document.fileURL,
              let origin = previewResourceState.beginSelection(for: document)
        else { return nil }

        return Task { @MainActor [weak self] in
            guard self?.mayPresentPreviewResourceSelection(origin, in: window) == true else {
                self?.previewResourceState.cancelSelection(origin)
                return
            }
            guard let selection = await chooser(window, documentURL) else {
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
