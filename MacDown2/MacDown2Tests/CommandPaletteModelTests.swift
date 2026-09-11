import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextFilters
import Themes
import Workspace

@Suite("CommandPaletteModel")
@MainActor
struct CommandPaletteModelTests {
    private static let sampleAppCommands: [AppPaletteCommand] = [
        AppPaletteCommand(id: "newFile", title: "New File") { _, _ in },
        AppPaletteCommand(id: "save", title: "Save") { _, _ in },
    ]

    private static func filter(_ name: String) -> TextFilterCommand {
        TextFilterCommand(id: "\(name).sh", name: name, executableURL: URL(fileURLWithPath: "/tmp/\(name).sh"))
    }

    @Test func combinesAppCommandsAndTextFiltersWithNoQuery() {
        let rows = CommandPaletteModel.filteredRows(
            query: "", appCommands: Self.sampleAppCommands, textFilters: [Self.filter("Uppercase")]
        )
        #expect(rows.map(\.title) == ["New File", "Save", "Uppercase"])
        #expect(rows.map(\.kind) == [.appCommand, .appCommand, .textFilter])
    }

    @Test func queryFiltersCaseInsensitivelyAcrossBothKinds() {
        let rows = CommandPaletteModel.filteredRows(
            query: "sav", appCommands: Self.sampleAppCommands, textFilters: [Self.filter("Uppercase")]
        )
        #expect(rows.map(\.title) == ["Save"])
    }

    @Test func emptyQueryAfterTrimmingWhitespaceShowsEverything() {
        let rows = CommandPaletteModel.filteredRows(
            query: "   ", appCommands: Self.sampleAppCommands, textFilters: []
        )
        #expect(rows.count == 2)
    }

    @Test func noMatchesProducesAnEmptyList() {
        let rows = CommandPaletteModel.filteredRows(
            query: "nonexistent", appCommands: Self.sampleAppCommands, textFilters: []
        )
        #expect(rows.isEmpty)
    }

    @Test func moveSelectionWrapsAroundInBothDirections() {
        let model = CommandPaletteModel(appCommands: Self.sampleAppCommands, discoverTextFilters: { [] })
        #expect(model.selectedIndex == 0)

        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func moveSelectionOnAnEmptyListDoesNothing() {
        let model = CommandPaletteModel(appCommands: [], discoverTextFilters: { [] })
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func invokingSelectedAppCommandDispatchesToAppHandler() {
        let model = CommandPaletteModel(appCommands: Self.sampleAppCommands, discoverTextFilters: { [] })
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences(),
            recentFolderRoots: RecentFolderRoots(preferences: FileTreePreferences()),
            appSettings: AppSettingsModel()
        )

        var invokedAppCommandID: String?
        model.invokeSelected(
            coordinator: coordinator,
            originController: nil,
            appHandler: { command, _, _ in invokedAppCommandID = command.id },
            filterHandler: { _ in Issue.record("expected the app handler, not the filter handler") }
        )

        #expect(invokedAppCommandID == "newFile")
    }

    @Test func invokingSelectedTextFilterDispatchesToFilterHandler() {
        let command = Self.filter("Uppercase")
        let model = CommandPaletteModel(appCommands: [], discoverTextFilters: { [command] })
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences(),
            recentFolderRoots: RecentFolderRoots(preferences: FileTreePreferences()),
            appSettings: AppSettingsModel()
        )

        var invokedFilterID: String?
        model.invokeSelected(
            coordinator: coordinator,
            originController: nil,
            appHandler: { _, _, _ in Issue.record("expected the filter handler, not the app handler") },
            filterHandler: { command in invokedFilterID = command.id }
        )

        #expect(invokedFilterID == command.id)
    }

    @Test func refreshRowsRescansTextFiltersOnEveryCall() {
        var discoveredCommands: [TextFilterCommand] = []
        let model = CommandPaletteModel(appCommands: [], discoverTextFilters: { discoveredCommands })
        #expect(model.rows.isEmpty)

        discoveredCommands = [Self.filter("Uppercase")]
        model.refreshRows()

        #expect(model.rows.map(\.title) == ["Uppercase"])
    }

    // MARK: - Post-review finding #8: unavailable commands are omitted

    @Test func unavailableAppCommandsAreFilteredRows() {
        let rows = CommandPaletteModel.filteredRows(
            query: "",
            appCommands: Self.sampleAppCommands,
            isAppCommandAvailable: { $0.id != "save" },
            textFilters: []
        )
        #expect(rows.map(\.id) == ["app.newFile"])
    }

    @Test func textFiltersUnavailableOmitsEveryDiscoveredFilterRow() {
        let rows = CommandPaletteModel.filteredRows(
            query: "",
            appCommands: [],
            textFilters: [Self.filter("Uppercase")],
            textFiltersAvailable: false
        )
        #expect(rows.isEmpty)
    }

    @Test func modelAppliesTheAvailabilityPredicateItWasConstructedWith() {
        let model = CommandPaletteModel(
            appCommands: Self.sampleAppCommands,
            discoverTextFilters: { [] },
            isAppCommandAvailable: { $0.id != "save" }
        )
        #expect(model.rows.map(\.title) == ["New File"])
    }

    // MARK: - Post-review finding #9: invocation uses the discovery snapshot

    @Test func invocationDispatchesTheSnapshotEvenIfDiscoveryWouldNowReturnSomethingElse() {
        let command = Self.filter("Uppercase")
        var discoveredCommands = [command]
        let model = CommandPaletteModel(appCommands: [], discoverTextFilters: { discoveredCommands })
        // Simulate the file vanishing (or discovery otherwise changing)
        // between the palette opening and Return — invocation must still
        // dispatch the row the user actually saw and selected.
        discoveredCommands = []
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences(),
            recentFolderRoots: RecentFolderRoots(preferences: FileTreePreferences()),
            appSettings: AppSettingsModel()
        )

        var invokedFilterID: String?
        model.invokeSelected(
            coordinator: coordinator,
            originController: nil,
            appHandler: { _, _, _ in Issue.record("expected the filter handler") },
            filterHandler: { command in invokedFilterID = command.id }
        )

        #expect(invokedFilterID == command.id)
    }

    // MARK: - Second-adversarial-pass required change A: no palette Export

    @Test func standardCommandsContainNoExportRow() {
        #expect(AppPaletteCommand.standard.contains { $0.id == "export" } == false)
        #expect(AppPaletteCommand.standard.contains { $0.title.contains("Export") } == false)
    }
}
