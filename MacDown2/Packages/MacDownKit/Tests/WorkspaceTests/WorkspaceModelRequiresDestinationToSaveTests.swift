@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Third-adversarial-pass finding #5: the command palette's "Save" row
/// needs to know, *before* calling `save()`, whether doing so would need
/// to prompt for a destination — so it can route to its own
/// explicit-origin destination flow instead of letting `save()` fall
/// back to its ambient one. `requiresDestinationToSave` is the exact
/// condition that decision depends on; these are its three cases in
/// isolation. (The two-window, already-backed-document case — where
/// `requiresDestinationToSave` is `false` and the palette's "Save" row
/// takes the plain `saveDocument()` path end to end — is covered
/// separately in the App target's `PaletteOriginTargetingTests`; the
/// other two cases route through a real destination panel this package's
/// tests cannot drive headlessly, so this is their only automated
/// coverage — see the PR's manual verification matrix for the rest.)
@MainActor
@Suite("WorkspaceModel requiresDestinationToSave")
struct RequiresDestinationToSaveTests {
    @Test func noActiveDocumentDoesNotRequireADestination() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        #expect(!model.requiresDestinationToSave)
    }

    @Test func anUntitledDocumentRequiresADestination() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("hello") }

        #expect(model.requiresDestinationToSave)
    }

    @Test func aDocumentWithAnUnavailableBackingRequiresADestination() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("missing.md")
        let document = FileDocument(fileURL: url, text: "keep")
            .updatingText("keep")
            .markingBackingUnavailable(.missingOrMoved)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        #expect(model.requiresDestinationToSave)
    }

    @Test func anOrdinaryBackedDocumentDoesNotRequireADestination() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("normal.md")
        try? "keep".write(to: url, atomically: true, encoding: .utf8)
        let document = FileDocument(fileURL: url, text: "keep").updatingText("changed")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        #expect(!model.requiresDestinationToSave)
    }
}
