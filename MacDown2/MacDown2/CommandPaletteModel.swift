import Observation
import TextFilters

/// One row the palette can display and invoke: either a fixed app command
/// or a discovered text filter, visibly distinguished (`kind`) so the user
/// never mistakes a script they installed for first-party functionality
/// (epic-14-implementation.md §10).
struct CommandPaletteRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case appCommand
        case textFilter
    }

    let id: String
    let title: String
    let kind: Kind
}

/// Pure row-building/selection logic for the command palette
/// (epic-14-implementation.md §17 Slice 7), kept free of any AppKit/SwiftUI
/// presentation so it is directly testable without presenting UI.
@MainActor
@Observable
final class CommandPaletteModel {
    var query = "" {
        didSet { refreshRows() }
    }

    private(set) var selectedIndex = 0
    private(set) var rows: [CommandPaletteRow] = []

    private let appCommands: [AppPaletteCommand]
    private let discoverTextFilters: () -> [TextFilterCommand]

    init(
        appCommands: [AppPaletteCommand] = AppPaletteCommand.standard,
        discoverTextFilters: @escaping () -> [TextFilterCommand] = { TextFilterCommandDiscovery.discoverCommands() }
    ) {
        self.appCommands = appCommands
        self.discoverTextFilters = discoverTextFilters
        refreshRows()
    }

    /// Re-scans for text filters and re-applies the current query —
    /// discovered commands can change between two palette openings (§7.2).
    func refreshRows() {
        rows = Self.filteredRows(query: query, appCommands: appCommands, textFilters: discoverTextFilters())
        selectedIndex = rows.isEmpty ? 0 : min(selectedIndex, rows.count - 1)
    }

    static func filteredRows(
        query: String,
        appCommands: [AppPaletteCommand],
        textFilters: [TextFilterCommand]
    ) -> [CommandPaletteRow] {
        let appRows = appCommands.map { CommandPaletteRow(id: "app.\($0.id)", title: $0.title, kind: .appCommand) }
        let filterRows = textFilters.map { CommandPaletteRow(id: "filter.\($0.id)", title: $0.name, kind: .textFilter) }
        let all = appRows + filterRows
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// Invokes the currently selected row, dispatching to `appHandler` or
    /// `filterHandler` by matching the row's `id` back to its source
    /// command — the row itself carries no closure, keeping
    /// `CommandPaletteRow` a plain, `Equatable` value for testing.
    func invokeSelected(
        coordinator: WindowCoordinator,
        appHandler: (AppPaletteCommand, WindowCoordinator) -> Void,
        filterHandler: (TextFilterCommand) -> Void
    ) {
        guard let row = rows[safe: selectedIndex] else { return }
        switch row.kind {
        case .appCommand:
            guard let command = appCommands.first(where: { row.id == "app.\($0.id)" }) else { return }
            appHandler(command, coordinator)
        case .textFilter:
            guard let command = discoverTextFilters().first(where: { row.id == "filter.\($0.id)" }) else { return }
            filterHandler(command)
        }
    }
}
