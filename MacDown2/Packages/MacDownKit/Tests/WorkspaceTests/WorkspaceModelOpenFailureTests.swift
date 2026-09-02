@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// `openFile()` must surface the real reason a file could not be opened —
/// not a fabricated `.fileReadNoSuchFile`, which used to be reported even
/// for a permission error or a corrupt-encoding file. Kept in its own file
/// rather than growing `WorkspaceModelFileTests`, already close to the
/// file-length budget.
@MainActor
@Suite("WorkspaceModel open failure")
struct WorkspaceModelOpenFailureTests {
    @Test func openMissingFileReportsFileMissing() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("missing.md")

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()

        #expect(model.activeDocument == nil)
        guard case let .openFailed(underlying) = model.lastError else {
            Issue.record("Expected .openFailed, got \(String(describing: model.lastError))")
            return
        }
        guard case .fileMissing = underlying else {
            Issue.record("Expected .fileMissing, got \(underlying)")
            return
        }
    }

    @Test func successfulOpenAfterAFailureClearsTheError() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let missingURL = directory.appendingPathComponent("missing.md")
        let realURL = directory.appendingPathComponent("real.md")
        _ = try? FileStore().write("content", to: realURL)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = missingURL
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        #expect(model.lastError != nil)

        panel.nextFileURL = realURL
        await model.openFile()

        #expect(model.lastError == nil)
        #expect(model.activeDocument?.text == "content")
    }
}
