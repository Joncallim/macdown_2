import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// #183 R01: the status bar's encoding actions act on the window that owns the
/// bar, never on whichever window happens to be key when the action runs.
@MainActor
struct StatusBarEncodingOriginTests {
    private func makeCoordinator(recovery: RecoveryBuffer) -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            sessionStore: NoOpSessionStore(),
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    private func addWindow(
        to coordinator: WindowCoordinator,
        file: URL,
        recovery: RecoveryBuffer
    ) throws -> WindowController {
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: file, recoveryBuffer: recovery).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers.append(controller)
        return controller
    }

    @Test func saveWithEncodingActsOnTheOwningWindowNotTheKeyOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(recovery: recovery)
        let fileA = directory.appendingPathComponent("a.txt")
        let fileB = directory.appendingPathComponent("b.txt")
        try "alpha".write(to: fileA, atomically: true, encoding: .utf8)
        try "bravo".write(to: fileB, atomically: true, encoding: .utf8)
        let windowA = try addWindow(to: coordinator, file: fileA, recovery: recovery)
        let windowB = try addWindow(to: coordinator, file: fileB, recovery: recovery)
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)

        // Neither window is key in a test, so the old key-window routing would
        // have done nothing; routed by owner, B's bar changes B only.
        coordinator.saveDocument(in: windowB.model, withEncoding: latin1)
        for _ in 0 ..< 500 where windowB.model.activeDocument?.encoding != latin1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(windowB.model.activeDocument?.encoding == latin1)
        #expect(windowA.model.activeDocument?.encoding == .utf8Default)
    }
}
