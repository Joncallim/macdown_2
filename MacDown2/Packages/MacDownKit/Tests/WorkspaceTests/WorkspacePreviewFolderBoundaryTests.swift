import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("Preview folder association publication")
struct WorkspacePreviewFolderBoundaryTests {
    @Test func folderSelectionAndRemapNotifyBeforeNewAssociation() {
        let model = WorkspaceModel(tabStore: TabStore(sessionStore: FakeSessionStore()), stateStore: FakeStateStore())
        let first = URL(fileURLWithPath: "/tmp/preview-first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/preview-second", isDirectory: true)
        let third = URL(fileURLWithPath: "/tmp/preview-third", isDirectory: true)
        model.setFolderRoot(first)
        var oldRoots: [URL?] = []
        model.setFolderAssociationWillChange {
            oldRoots.append(model.folderURL)
        }

        model.setFolderRoot(first)
        #expect(oldRoots.isEmpty)
        model.setFolderRoot(second)
        #expect(oldRoots == [first.standardizedFileURL])
        model.remapFolderRoot(from: second, to: third)
        #expect(oldRoots == [first.standardizedFileURL, second.standardizedFileURL])
        #expect(model.folderURL == third.standardizedFileURL)
    }
}
