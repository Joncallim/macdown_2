import FileCore
import Workspace

extension WindowCoordinator {
    func makeWindowModel(panel: (any FilePanelProviding)? = nil) -> WorkspaceModel {
        let tabStore = TabStore(sessionStore: NoOpSessionStore(), recoveryBuffer: recoveryBuffer)
        let model = WorkspaceModel(
            tabStore: tabStore,
            stateStore: workspaceStateStore,
            layoutBroadcaster: sidebarLayoutBroadcaster,
            panel: panel ?? panelProvider
        )
        model.setSaveAsSessionPublisher { [weak self, weak model] in
            guard let self, let model else { return false }
            let result = await saveSessionResult(allowingSaveAsPublicationFor: model)
            return result.persisted
        }
        tabStore.setRenameSessionPublisher { [weak self, weak model] in
            guard let self, let model else { return false }
            return await saveSessionResult(allowingSaveAsPublicationFor: model).persisted
        }
        model.onDocumentWritten = { [weak self] url in self?.recentFileDocuments.noteWrite(of: url) }
        return model
    }
}
