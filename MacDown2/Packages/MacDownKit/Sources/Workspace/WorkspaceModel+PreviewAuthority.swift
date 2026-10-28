import Foundation

public extension WorkspaceModel {
    /// Runs before the window's folder association changes. It never creates file access; a preview owner uses it
    /// to revoke old authority before an updated association can be observed.
    func setFolderAssociationWillChange(_ callback: (@MainActor () -> Void)?) {
        precondition(callback == nil || folderAssociationWillChange == nil, "Folder observer already installed")
        folderAssociationWillChange = callback
    }
}
