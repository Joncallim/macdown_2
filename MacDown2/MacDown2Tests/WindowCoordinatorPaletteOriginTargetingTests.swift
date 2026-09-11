import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Post-review finding #4: the command palette panel is `NSApp.keyWindow`
/// while its commands' async continuations run, so a continuation that
/// re-resolved its target from `NSApp.keyWindow` (instead of the explicit
/// origin `WindowController` the palette captured when it opened) would
/// silently act on whichever *document* window the OS considered key by the
/// time the `await` returned — not necessarily the window the user actually
/// invoked the palette from.
///
/// These tests build two real document windows/controllers, A and B, and
/// exercise each previously-leaking operation with an explicit A origin
/// while B sits in the coordinator as a plausible (and, in a real run,
/// frequently *actual*) ambient-key distractor. None of these tests rely on
/// `NSApp.keyWindow` actually being B — that would need real WindowServer
/// focus changes, which are unreliable in an automated/CI run and irrelevant
/// to what's under test here: whether the operation's *target* is the
/// explicit origin at all, independent of whatever `NSApp.keyWindow`
/// happens to be. A leak would show up identically here, since in a
/// headless test run `NSApp.keyWindow` is never actually A or B — exactly
/// the "elsewhere" case the leak silently broke.
///
/// "Open…" and "Open Folder…"'s palette actions themselves present a real
/// `NSOpenPanel`, which cannot be driven headlessly, so those two are tested
/// one layer below the panel — at `openDocument(at:relativeTo:)` and
/// `openFolder(_:in:)`, the exact methods the panel's completion handler
/// calls into, and exactly where the finding #4 leak lived ("deeper in
/// async chains").
@MainActor
@Suite("WindowCoordinator palette origin targeting (finding #4)")
struct PaletteOriginTargetingTests {
    private struct Fixture {
        let coordinator: WindowCoordinator
        let controllerA: WindowController
        let controllerB: WindowController
        let recoveryBuffer: RecoveryBuffer
        let rootDirectory: URL
    }

    private static func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: rootDirectory.appendingPathComponent("Recovery"))
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            recoveryBuffer: recoveryBuffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let controllerA = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        let controllerB = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controllerA, controllerB]
        return Fixture(
            coordinator: coordinator,
            controllerA: controllerA,
            controllerB: controllerB,
            recoveryBuffer: recoveryBuffer,
            rootDirectory: rootDirectory
        )
    }

    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - New File's post-creation open

    @Test func newFileFromAnExplicitOriginCreatesAndOpensUnderThatOriginNotAnotherOpenWindow() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let dirA = fixture.rootDirectory.appendingPathComponent("A", isDirectory: true)
        let dirB = fixture.rootDirectory.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        fixture.controllerA.model.setFolderRoot(dirA)
        await fixture.controllerA.fileTreeModel.setRoot(dirA)
        fixture.controllerB.model.setFolderRoot(dirB)
        await fixture.controllerB.fileTreeModel.setRoot(dirB)

        let controllersBefore = fixture.coordinator.controllers.count
        fixture.coordinator.createInFolder(isDirectory: false, controller: fixture.controllerA)
        await Self.waitUntil { fixture.coordinator.controllers.count > controllersBefore }
        defer { fixture.coordinator.controllers.last?.close() }

        // The created file itself lives under A's folder root, not B's.
        #expect(fixture.controllerA.fileTreeModel.selectedURL?.deletingLastPathComponent().standardizedFileURL == dirA
            .standardizedFileURL)
        #expect(fixture.controllerB.model.tabStore.tabs.isEmpty)
        #expect(fixture.controllerA.fileTreeModel.pendingOpenURL == nil)

        // Opening the newly created file — like "Open…" — creates a new
        // tabbed window; it must join A's tab group, not B's or a
        // standalone one (post-review finding #4's actual leak point:
        // this post-creation `openDocument` call used to be able to
        // resolve `NSApp.keyWindow` here instead of `controller.window`).
        let opened = try #require(fixture.coordinator.controllers.last)
        #expect(opened !== fixture.controllerA)
        #expect(opened !== fixture.controllerB)
        let openedWindow = try #require(opened.window)
        let originWindow = try #require(fixture.controllerA.window)
        #expect(openedWindow.tabGroup === originWindow.tabGroup)
        #expect(opened.model.activeDocument?.fileURL?.deletingLastPathComponent().standardizedFileURL == dirA
            .standardizedFileURL)
    }

    // MARK: - Open… (below the panel)

    @Test func openDocumentWithAnExplicitOriginTabsUnderThatOriginNotAnotherOpenWindow() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        // Deliberately neither controller is shown/ordered front here: this
        // repo enables native `tabbingMode = .preferred`, and on a machine
        // with "Prefer tabs: Always" this makes AppKit itself auto-merge any
        // two *visible* windows of the same kind into one tab group — a
        // real OS behavior that would swamp the one signal this test cares
        // about (which window `addTabbedWindow` was explicitly called
        // with). Never showing A/B isolates that signal: any tab-group
        // merge the assertion below observes can only be this codepath's
        // own `addTabbedWindow(tab, ordered:)` call, targeting the explicit
        // `relativeTo` window — not ambient OS grouping.
        defer { fixture.controllerA.close() }
        let fileToOpen = fixture.rootDirectory.appendingPathComponent("toOpen.md")
        try "hello".write(to: fileToOpen, atomically: true, encoding: .utf8)

        await fixture.coordinator.openDocument(at: fileToOpen, relativeTo: fixture.controllerA.window)

        let opened = try #require(fixture.coordinator.controllers.last)
        defer { opened.close() }
        #expect(opened !== fixture.controllerA)
        #expect(opened !== fixture.controllerB)
        let openedWindow = try #require(opened.window)
        let originWindow = try #require(fixture.controllerA.window)
        #expect(openedWindow.tabGroup === originWindow.tabGroup)
    }

    // MARK: - Open Folder… (below the panel)

    @Test func openFolderWithAnExplicitOriginSetsThatOriginsRootNotAnotherOpenWindows() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let folderToOpen = fixture.rootDirectory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderToOpen, withIntermediateDirectories: true)

        fixture.coordinator.openFolder(folderToOpen, in: fixture.controllerA)
        await Self.waitUntil { fixture.controllerA.fileTreeModel.root != nil }

        #expect(fixture.controllerA.model.folderURL?.standardizedFileURL == folderToOpen.standardizedFileURL)
        #expect(fixture.controllerA.fileTreeModel.root?.standardizedFileURL == folderToOpen.standardizedFileURL)
        #expect(fixture.controllerB.model.folderURL == nil)
        #expect(fixture.controllerB.fileTreeModel.root == nil)
    }

    // MARK: - Save As's destination (Workspace-layer intent, below the panel)

    @Test func saveAsToAnExplicitURLAppliesOnlyToTheOriginsOwnModel() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let sourceA = fixture.rootDirectory.appendingPathComponent("a-source.md")
        let sourceB = fixture.rootDirectory.appendingPathComponent("b-source.md")
        try "a".write(to: sourceA, atomically: true, encoding: .utf8)
        try "b".write(to: sourceB, atomically: true, encoding: .utf8)
        let destination = fixture.rootDirectory.appendingPathComponent("a-destination.md")

        let documentA = try FileDocument(fileURL: sourceA, recoveryBuffer: fixture.recoveryBuffer)
            .load().updatingText("draft-a")
        fixture.controllerA.model.tabStore.newTab(document: documentA)
        let documentB = try FileDocument(fileURL: sourceB, recoveryBuffer: fixture.recoveryBuffer)
            .load().updatingText("draft-b")
        fixture.controllerB.model.tabStore.newTab(document: documentB)

        let expectedA = try #require(fixture.controllerA.model.activeDocument)
        await fixture.controllerA.model.saveAs(to: destination, expecting: expectedA)

        #expect(fixture.controllerA.model.activeDocument?.fileURL?.standardizedFileURL == destination
            .standardizedFileURL)
        #expect(fixture.controllerB.model.activeDocument?.fileURL?.standardizedFileURL == sourceB.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - New Tab, Save, Close Tab, Toggle Sidebar: already explicit, regression-guarded here too

    @Test func newTabFromAnExplicitOriginTabsUnderThatOriginNotAnotherOpenWindow() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        // See the comment on the "Open…" test above for why A/B are
        // deliberately never shown here.
        defer { fixture.controllerA.close() }

        let command = try #require(AppPaletteCommand.standard.first { $0.id == "newTab" })
        command.action(fixture.coordinator, fixture.controllerA)

        let created = try #require(fixture.coordinator.controllers.last)
        defer { created.close() }
        let createdWindow = try #require(created.window)
        let originWindow = try #require(fixture.controllerA.window)
        #expect(createdWindow.tabGroup === originWindow.tabGroup)
    }

    @Test func saveFromAnExplicitOriginSavesOnlyThatOriginsDocument() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let sourceA = fixture.rootDirectory.appendingPathComponent("save-a.md")
        try "a".write(to: sourceA, atomically: true, encoding: .utf8)
        let documentA = try FileDocument(fileURL: sourceA, recoveryBuffer: fixture.recoveryBuffer)
            .load().updatingText("edited-a")
        fixture.controllerA.model.tabStore.newTab(document: documentA)
        #expect(fixture.controllerA.model.canSave)

        let command = try #require(AppPaletteCommand.standard.first { $0.id == "save" })
        command.action(fixture.coordinator, fixture.controllerA)
        await Self.waitUntil { fixture.controllerA.model.activeDocument?.state != .dirty }

        #expect(fixture.controllerA.model.activeDocument?.state != .dirty)
        #expect(try String(contentsOf: sourceA, encoding: .utf8) == "edited-a")
    }

    @Test func closeTabFromAnExplicitOriginClosesOnlyThatOriginsWindow() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        fixture.controllerA.showWindow(nil)
        fixture.controllerB.showWindow(nil)
        defer { fixture.controllerB.close() }

        let command = try #require(AppPaletteCommand.standard.first { $0.id == "closeTab" })
        command.action(fixture.coordinator, fixture.controllerA)

        #expect(!fixture.coordinator.controllers.contains { $0 === fixture.controllerA })
        #expect(fixture.coordinator.controllers.contains { $0 === fixture.controllerB })
    }

    @Test func toggleSidebarFromAnExplicitOriginTogglesOnlyThatOriginsSidebar() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let originalA = fixture.controllerA.model.sidebarVisible
        let originalB = fixture.controllerB.model.sidebarVisible

        let command = try #require(AppPaletteCommand.standard.first { $0.id == "toggleSidebar" })
        command.action(fixture.coordinator, fixture.controllerA)

        #expect(fixture.controllerA.model.sidebarVisible == !originalA)
        #expect(fixture.controllerB.model.sidebarVisible == originalB)
    }
}
