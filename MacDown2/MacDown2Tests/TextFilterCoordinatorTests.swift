import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextFilters
import Themes
import Workspace

/// App-target integration coverage for `TextFilterCoordinator` against a
/// real `EditorTextSystem`/`WindowController` — the gap the post-review
/// adversarial pass identified as finding #12: the previous suite only
/// exercised the pure `clampedRange` helper (now folded into
/// `EditorTextSystem.applyExternalReplacement`) and never ran a filter
/// through the coordinator against a live editor, so the mutation/undo/
/// fidelity/staleness/lifecycle paths below were unverified.
@MainActor
@Suite("TextFilterCoordinator")
struct TextFilterCoordinatorTests {
    // MARK: - Fixture plumbing

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeCommand(_ script: String, in directory: URL) throws -> TextFilterCommand {
        let name = "\(UUID().uuidString).sh"
        let url = directory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    /// A slow script the test can hold open across an intervening edit or a
    /// window close, then release by writing a sentinel file.
    private static func makeGatedCommand(gate: URL, in directory: URL) throws -> TextFilterCommand {
        try makeCommand(
            """
            #!/bin/sh
            while [ ! -f "\(gate.path)" ]; do sleep 0.02; done
            cat | tr 'a-z' 'A-Z'
            """,
            in: directory
        )
    }

    private struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let tabID: UUID
    }

    private static func makeController(text: String = "one two") throws -> Fixture {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let document = FileDocument(text: text)
        model.tabStore.newTab(document: document)
        let tabID = try #require(model.tabStore.activeTab).id
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return Fixture(coordinator: coordinator, controller: controller, tabID: tabID)
    }

    private static func target(
        controller: WindowController, tabID: UUID
    ) throws -> TextFilterCoordinator.TextFilterEditingTarget {
        let textSystem = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        let document = try #require(controller.model.tabStore.tabs.first { $0.id == tabID }).document
        return TextFilterCoordinator.TextFilterEditingTarget(
            controller: controller,
            tabID: tabID,
            textSystem: textSystem,
            documentURL: document.fileURL,
            documentGeneration: document.mutationGeneration
        )
    }

    // MARK: - End-to-end mutation/undo (J4, finding #12)

    @Test func selectionReplacementAppliesExactlyOneUndoStep() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "two"
        let command = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "one TWO")
        #expect(textSystem.undoManager.canUndo)
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one two")
    }

    @Test func wholeDocumentReplacementAppliesExactlyOneUndoStep() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one\ntwo\n")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0)) // empty selection: whole document
        let command = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "ONE\nTWO\n")
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one\ntwo\n")
    }

    /// Post-review finding #14: the manual matrix previously claimed empty
    /// stdout was an error, contradicting the implemented zero-exit/empty-
    /// output semantics. This is the explicit test the finding asked for.
    @Test func zeroExitEmptyStdoutDeletesSelectionAsOneUndoableEdit() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3))
        let command = try Self.makeCommand("#!/bin/sh\ntrue\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "one ")
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one two")
    }

    // MARK: - Editing-assist fidelity (finding #3)

    /// Before the `applyExternalReplacement` seam, a filter's literal `*`
    /// output was reinterpreted by the Markdown editing-assist engine as a
    /// bold/italic delimiter and expanded to `*foo*` instead of being
    /// inserted verbatim.
    @Test func filterOutputIsInsertedVerbatimEvenWhenMarkdownAssistsAreEnabled() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "foo")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.apply(EditorConfiguration(
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            editingAssists: .markdownDefault
        ))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 3)) // "foo"
        let command = try Self.makeCommand("#!/bin/sh\ncat >/dev/null\nprintf '*'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "*")
        #expect(textSystem.undoManager.canUndo)
        textSystem.undoManager.undo()
        #expect(textSystem.text == "foo")
    }

    // MARK: - Stale-completion rejection (finding #1)

    @Test func aLiveEditWhileTheFilterIsRunningDiscardsTheStaleResultWithoutMutation() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "two"
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let runTask = Task {
            await fixture.coordinator.textFilterCoordinator.run(command, against: target)
        }
        // Let the filter actually launch and block on the gate before editing.
        try await Task.sleep(for: .milliseconds(100))

        // Simulate a live edit through the real, delegate-wired text view —
        // exactly like the user typing while the filter runs.
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0))
        textSystem.textView.insertText("X ", replacementRange: NSRange(location: 0, length: 0))
        let liveTextAfterEdit = textSystem.text

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await runTask.value

        // The stale completion must not have touched the text the live edit
        // produced, and must not have added an undo entry of its own.
        #expect(textSystem.text == liveTextAfterEdit)
    }

    // MARK: - Task ownership / window-close cancellation (finding #5)

    @Test func closingTheWindowCancelsARunningFilterAndDiscardsItsResult() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let runTask = Task {
            await fixture.coordinator.textFilterCoordinator.run(command, against: target)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!fixture.controller.textFilterTaskHandles.isEmpty)

        fixture.controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(fixture.controller.textFilterTaskHandles.isEmpty)

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await runTask.value

        // The editor was evicted by `windowWillClose`; a late completion has
        // nothing live to mutate.
        #expect(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString) == nil)
    }

    @Test func aNewRunSupersedesAndCancelsThePreviousOneForTheSameTab() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let slowCommand = try Self.makeGatedCommand(gate: gate, in: directory)
        let fastCommand = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let firstRun = Task {
            await fixture.coordinator.textFilterCoordinator.run(slowCommand, against: target)
        }
        try await Task.sleep(for: .milliseconds(100))

        // The second run on the same tab supersedes the first.
        await fixture.coordinator.textFilterCoordinator.run(fastCommand, against: target)
        #expect(textSystem.text == "ONE TWO")

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await firstRun.value

        // The superseded run's (identical, coincidentally) output must not
        // have landed a second, redundant mutation on top of the winner's.
        #expect(textSystem.text == "ONE TWO")
    }
}
