import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextFilters
import Themes
import Workspace

/// Post-review finding #5: the palette must never keep offering, or be
/// able to invoke, a command against an origin that is no longer live —
/// whether because its window closed while the palette stayed open, or
/// because whatever made a row available simply stopped being true in the
/// interval between the last row rebuild and the user pressing Return.
@MainActor
@Suite("Command palette stale origin (finding #5)")
struct CommandPaletteStaleOriginTests {
    private static func makeCoordinatorAndController() -> (WindowCoordinator, WindowController) {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let controller = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return (coordinator, controller)
    }

    // MARK: - Origin closes while the palette is open

    @Test func closingTheOriginWindowDismissesTheOpenPaletteAndDoesNotBlockItsDeallocation() {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        weak var weakPanel: CommandPalettePanel?
        autoreleasepool {
            var panel: CommandPalettePanel? = CommandPalettePanel(
                coordinator: coordinator,
                originController: controller
            )
            coordinator.commandPalette = panel
            weakPanel = panel
            #expect(coordinator.commandPalette != nil)

            // The same call every real close path makes (`WindowController
            // +Close.swift`) before actually closing the window.
            coordinator.removeController(controller)

            #expect(coordinator.commandPalette == nil)
            panel = nil
        }

        // `close()` releases the window through AppKit's autorelease pool
        // rather than deallocating it inline, so the pool above — not just
        // dropping the local reference — is what proves nothing else
        // (in particular, nothing keyed off the now-closed `controller`)
        // still keeps the palette alive.
        #expect(weakPanel == nil)
    }

    @Test func removingAnUnrelatedControllerLeavesTheOpenPaletteAlone() {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        let other = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers.append(other)
        let panel = CommandPalettePanel(coordinator: coordinator, originController: controller)
        coordinator.commandPalette = panel

        coordinator.removeController(other)

        #expect(coordinator.commandPalette === panel)
    }

    // MARK: - An app command row goes stale before Return

    @Test func invocationRevalidatesAppCommandAvailabilityAndSkipsAStaleRow() {
        var available = true
        let command = AppPaletteCommand(id: "x", title: "X") { _, _ in }
        let model = CommandPaletteModel(
            appCommands: [command],
            discoverTextFilters: { [] },
            isAppCommandAvailable: { _ in available }
        )
        #expect(model.rows.map(\.id) == ["app.x"])

        // Goes stale in the interval between that row rebuild and Return —
        // e.g. the row's origin closed, or whatever made it available
        // stopped being true — without the palette re-scanning in between.
        available = false
        let (coordinator, _) = Self.makeCoordinatorAndController()
        var invoked = false
        model.invokeSelected(
            coordinator: coordinator,
            originController: nil,
            appHandler: { _, _, _ in invoked = true },
            filterHandler: { _ in Issue.record("expected no handler to run for a stale row") }
        )

        #expect(!invoked)
    }

    // MARK: - A text filter's origin disappears before Return

    @Test func invocationRevalidatesTextFilterAvailabilityAndSkipsAStaleRow() {
        var available = true
        let filter = TextFilterCommand(
            id: "uppercase.sh",
            name: "Uppercase",
            executableURL: URL(fileURLWithPath: "/tmp/uppercase.sh")
        )
        let model = CommandPaletteModel(
            appCommands: [],
            discoverTextFilters: { [filter] },
            textFiltersAvailable: { available }
        )
        #expect(model.rows.map(\.id) == ["filter.uppercase.sh"])

        // The origin's editing target disappeared (e.g. its window closed,
        // or the active tab lost its editor) after this row was built.
        available = false
        let (coordinator, _) = Self.makeCoordinatorAndController()
        var invoked = false
        model.invokeSelected(
            coordinator: coordinator,
            originController: nil,
            appHandler: { _, _, _ in Issue.record("expected no handler to run for a stale row") },
            filterHandler: { _ in invoked = true }
        )

        #expect(!invoked)
    }

    // MARK: - Toggle Sidebar requires a live origin (post-review finding #5)

    @Test func toggleSidebarIsUnavailableOnceItsOriginIsNoLongerALiveController() throws {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        let command = try #require(AppPaletteCommand.standard.first { $0.id == "toggleSidebar" })
        #expect(command.isAvailable(coordinator, controller))

        coordinator.controllers.removeAll { $0 === controller }

        #expect(!command.isAvailable(coordinator, controller))
    }

    // MARK: - No document origin at all (third-adversarial-pass finding #6)

    /// The palette can be opened with `originController == nil` (invoked
    /// while no document window is key). New Tab/Open…/Open Folder… used
    /// to have no availability guard of their own in that state, and each
    /// falls back to resolving its target from `NSApp.keyWindow` deeper in
    /// its own async chain when given a `nil` explicit target — which, by
    /// the time that resolves, is the palette panel itself. These must be
    /// hidden, not merely no-ops, whenever there is no live document
    /// origin to act on.
    @Test func newTabOpenAndOpenFolderAreUnavailableWithNoDocumentOrigin() throws {
        let (coordinator, _) = Self.makeCoordinatorAndController()
        for id in ["newTab", "open", "openFolder"] {
            let command = try #require(AppPaletteCommand.standard.first { $0.id == id })
            #expect(!command.isAvailable(coordinator, nil), "\(id) must be unavailable with no document origin")
        }
    }

    @Test func newTabOpenAndOpenFolderAreAvailableWithALiveDocumentOrigin() throws {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        for id in ["newTab", "open", "openFolder"] {
            let command = try #require(AppPaletteCommand.standard.first { $0.id == id })
            #expect(command.isAvailable(coordinator, controller), "\(id) must be available with a live document origin")
        }
    }
}
