@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// `isCreatingDocument` is what `ContentAreaView`'s empty state reads to
/// distinguish "no document, press ⌘N" from "the ⌘N you just pressed hasn't
/// landed yet" — `WindowCoordinator.newDocument(addAsTab:)` shows the window
/// before `newManagedDocument` resolves. The one real risk is the flag
/// getting stuck `true` on a failure exit; both paths are covered here.
@MainActor
@Suite("WorkspaceModel isCreatingDocument")
struct WorkspaceModelCreatingDocumentTests {
    @Test func isCreatingDocumentClearsAfterASuccessfulCreate() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        #expect(!model.isCreatingDocument)
        let published = await model.newManagedDocument()

        #expect(published)
        #expect(!model.isCreatingDocument)
    }

    @Test func isCreatingDocumentClearsWhenPublicationIsDeclined() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        let published = await model.newManagedDocument(shouldPublish: { false })

        #expect(!published)
        #expect(!model.isCreatingDocument)
        #expect(model.activeDocument == nil)
    }
}
