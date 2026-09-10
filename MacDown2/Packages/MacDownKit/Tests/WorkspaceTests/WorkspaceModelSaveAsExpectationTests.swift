@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// A save panel is open for as long as the user takes to answer it, and the
/// active document can change underneath it — an external-change reload
/// replaces it, or another tab is activated. Neither is blocked by a sheet.
///
/// `saveAs(to:expecting:)` therefore writes the document the Save As was
/// *started for*, and abandons the save if that document is no longer the
/// active one. These tests pin that: the split into a panel-presenting
/// `saveAs()` plus a URL-taking `saveAs(to:expecting:)` (so the command
/// palette could bind its own panel to an explicit origin window) briefly
/// dropped the guard by re-reading `tabStore.activeDocument` after the panel
/// and checking `isCurrent` against it — a comparison of the active document
/// with itself, which is always true.
@MainActor
@Suite("WorkspaceModel Save As destination expectation")
struct WorkspaceModelSaveAsExpectationTests {
    /// The damaging case: the user picks a filename for document A, and B is
    /// active by the time the panel returns. Writing B's contents to the name
    /// chosen for A — and rebinding B to it — must not happen.
    @Test func saveAsDoesNotWriteADifferentDocumentThatBecameActiveWhileThePanelWasUp() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sourceA = directory.appendingPathComponent("a.md")
        let sourceB = directory.appendingPathComponent("b.md")
        let destination = directory.appendingPathComponent("chosen-for-a.md")
        _ = try FileStore().write("alpha", to: sourceA)
        _ = try FileStore().write("beta", to: sourceB)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: sourceA).load())
        let tabA = try #require(tabStore.activeTab).id
        try tabStore.newTab(document: FileDocument(fileURL: sourceB).load())
        let tabB = try #require(tabStore.activeTab).id
        tabStore.activate(tabA)
        #expect(tabStore.activeDocument?.fileURL?.standardizedFileURL == sourceA.standardizedFileURL)

        let panel = InterposingPanelProvider(destination: destination) {
            tabStore.activate(tabB)
        }
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(
            !FileManager.default.fileExists(atPath: destination.path),
            "B's contents must not be written to the destination the user chose for A"
        )
        #expect(
            model.activeDocument?.fileURL?.standardizedFileURL == sourceB.standardizedFileURL,
            "B must not be rebound to a destination chosen for a different document"
        )
        #expect(try FileStore().read(from: sourceA).content == "alpha")
        #expect(try FileStore().read(from: sourceB).content == "beta")
    }

    /// The same guard for the more ordinary case: the *same* document is
    /// replaced (an external-change reload) while the panel is up.
    @Test func saveAsAbandonsTheSaveIfItsOwnDocumentWasReplacedWhileThePanelWasUp() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("on disk", to: source)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let panel = InterposingPanelProvider(destination: destination) {
            tabStore.updateActiveDocument { $0.edited(text: "reloaded from disk") }
        }
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(model.activeDocument?.fileURL?.standardizedFileURL == source.standardizedFileURL)
    }

    /// Control: nothing changes under the panel, so the save proceeds.
    @Test func saveAsWritesTheDocumentItWasStartedForWhenNothingChanges() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("content", to: source)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let panel = InterposingPanelProvider(destination: destination) {}
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(model.activeDocument?.fileURL?.standardizedFileURL == destination.standardizedFileURL)
        #expect(try FileStore().read(from: destination).content == "content")
    }
}

/// A panel provider that runs `duringPanel` while the "panel" is up — i.e.
/// after Save As has captured the document it is saving and before it has a
/// URL to save it to. That interval is exactly the one a real sheet leaves
/// open to external-change reloads and tab activations.
private final class InterposingPanelProvider: FilePanelProviding, @unchecked Sendable {
    private let destination: URL
    private let duringPanel: @MainActor () -> Void

    init(destination: URL, duringPanel: @escaping @MainActor () -> Void) {
        self.destination = destination
        self.duringPanel = duringPanel
    }

    func chooseFile() async -> URL? {
        nil
    }

    func chooseFolder() async -> URL? {
        nil
    }

    func chooseSaveLocation(defaultName _: String, format _: FileFormat) async -> URL? {
        await MainActor.run { duringPanel() }
        return destination
    }
}
