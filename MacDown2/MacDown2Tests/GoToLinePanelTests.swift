import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// EPIC-22 Slice 2b — a real-`NSPanel`-mounted `GoToLinePanel` integration
/// test, per `planning/epic-22-implementation.md` §6.7's test commitment
/// (found missing by hostile review of PR #126). Calls `jump(to:)` directly
/// rather than driving the SwiftUI text field/button: `GoToLineView`'s
/// `onSubmit` closure forwards to it with no intervening logic of its own,
/// so this exercises the exact production code path, matching this
/// codebase's established `EditorViewRealMountTests` precedent for calling
/// a production method directly when the only thing skipped is trivial
/// SwiftUI plumbing around it.
@MainActor
@Suite("GoToLinePanel")
struct GoToLinePanelTests {
    private struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let textSystem: EditorTextSystem
    }

    private func makeFixture(text: String = "one\ntwo\nthree\nfour\nfive") throws -> Fixture {
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
        let textSystem = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        return Fixture(coordinator: coordinator, controller: controller, textSystem: textSystem)
    }

    // MARK: - jump(to:)

    @Test func jumpsToASpecificLine() throws {
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        defer { panel.close() }

        panel.jump(to: "3")

        let expectedOffset = fixture.textSystem.lineIndex.utf16Offset(
            forLine: 3,
            column: 1,
            in: fixture.textSystem.text as NSString
        )
        #expect(fixture.textSystem.selectedRange == NSRange(location: expectedOffset, length: 0))
    }

    @Test func jumpsToALineAndColumn() throws {
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        defer { panel.close() }

        panel.jump(to: "2:3")

        let expectedOffset = fixture.textSystem.lineIndex.utf16Offset(
            forLine: 2,
            column: 3,
            in: fixture.textSystem.text as NSString
        )
        #expect(fixture.textSystem.selectedRange == NSRange(location: expectedOffset, length: 0))
    }

    @Test func outOfRangeLineClampsToTheLastLine() throws {
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        defer { panel.close() }

        panel.jump(to: "999")

        let expectedOffset = fixture.textSystem.lineIndex.utf16Offset(
            forLine: 5,
            column: 1,
            in: fixture.textSystem.text as NSString
        )
        #expect(fixture.textSystem.selectedRange == NSRange(location: expectedOffset, length: 0))
    }

    @Test func malformedInputDefaultsToLineOne() throws {
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        defer { panel.close() }

        panel.jump(to: "not a number")

        #expect(fixture.textSystem.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test func aLeadingColonMeansColumnOnTheDefaultLineNotALineNumber() throws {
        // Regression test for the hostile-review finding: ":3" must not
        // silently become "line 3" (dropping the empty line component via
        // `omittingEmptySubsequences: true` would shift "3" into the line
        // position).
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        defer { panel.close() }

        panel.jump(to: ":3")

        let expectedOffset = fixture.textSystem.lineIndex.utf16Offset(
            forLine: 1,
            column: 3,
            in: fixture.textSystem.text as NSString
        )
        #expect(fixture.textSystem.selectedRange == NSRange(location: expectedOffset, length: 0))
    }

    // MARK: - Lifecycle

    @Test func closingThePanelReleasesTheCoordinatorsStrongReference() throws {
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        fixture.coordinator.goToLinePanel = panel

        panel.close()

        #expect(fixture.coordinator.goToLinePanel == nil)
    }

    @Test func closingTheOriginWindowClosesAnOpenGoToLinePanel() throws {
        // Mirrors the command palette's own origin-close auto-release
        // (`WindowCoordinator.removeController`) -- found missing for
        // GoToLinePanel by hostile review of PR #126, then fixed there.
        let fixture = try makeFixture()
        let panel = GoToLinePanel(coordinator: fixture.coordinator, originController: fixture.controller)
        fixture.coordinator.goToLinePanel = panel
        defer { panel.close() }

        fixture.coordinator.removeController(fixture.controller)

        #expect(fixture.coordinator.goToLinePanel == nil)
    }

    @Test func jumpDoesNothingIfThereIsNoOriginController() {
        let preferences = FileTreePreferences()
        let orphanCoordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let panel = GoToLinePanel(coordinator: orphanCoordinator, originController: nil)
        defer { panel.close() }

        // The real assertion is that this does not crash with no origin
        // controller (and hence no `EditorTextSystem`) to act on at all.
        panel.jump(to: "3")
    }
}
