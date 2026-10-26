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

    @Test func successfulOpenDoesNotClearANewerSaveError() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("real.md")
        _ = try FileStore().write("content", to: url)
        let panel = HeldFilePanel(url: url)
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        let opening = Task { await model.openFile() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await !panel.hasPendingChoice, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await panel.hasPendingChoice else {
            await panel.release()
            await opening.value
            Issue.record("open did not reach the held file panel")
            return
        }

        model.lastError = .textNotRepresentable(encodingName: "Windows-1252")
        await panel.release()
        await opening.value

        #expect(model.activeDocument?.text == "content")
        guard case .textNotRepresentable? = model.lastError else {
            Issue.record("a newer Save error was erased by the older open")
            return
        }
    }

    @Test func heldPanelReleaseBeforeAdmissionIsBuffered() async {
        let url = URL(fileURLWithPath: "/tmp/held-panel-test.md")
        let panel = HeldFilePanel(url: url)
        await panel.release()

        #expect(await panel.chooseFile() == url)
    }
}

private actor HeldFilePanel: FilePanelProviding {
    let url: URL
    private var pendingChoice: CheckedContinuation<URL?, Never>?
    private var released = false

    init(url: URL) {
        self.url = url
    }

    var hasPendingChoice: Bool {
        pendingChoice != nil
    }

    func chooseFile() async -> URL? {
        if released {
            return url
        }
        return await withCheckedContinuation { continuation in
            pendingChoice = continuation
        }
    }

    func release() {
        released = true
        pendingChoice?.resume(returning: url)
        pendingChoice = nil
    }

    func chooseFolder() async -> URL? {
        nil
    }

    func chooseSaveLocation(defaultName _: String, format _: FileFormat) async -> URL? {
        nil
    }
}
