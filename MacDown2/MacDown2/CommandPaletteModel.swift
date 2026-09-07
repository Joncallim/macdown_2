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
        didSet { applyFilter() }
    }

    private(set) var selectedIndex = 0
    private(set) var rows: [CommandPaletteRow] = []

    private let appCommands: [AppPaletteCommand]
    private let discoverTextFilters: () -> [TextFilterCommand]
    private let isAppCommandAvailable: (AppPaletteCommand) -> Bool
    /// A live closure, not a snapshot — see `CommandPalettePanel`'s init
    /// (post-review finding #5): whether text filters are available can
    /// change while the palette stays open, so this is re-evaluated on
    /// every row rebuild instead of being fixed at palette-open time.
    private let textFiltersAvailable: () -> Bool

    /// The filter list rows are currently built from. Invocation
    /// (`invokeSelected`) looks a chosen row up here — the *same* snapshot
    /// the row was rendered from — rather than rescanning disk, so a file
    /// that vanishes between discovery and Return still reaches
    /// `filterHandler` and becomes the ordinary, visible `.launchFailed`
    /// `TextFilterRunner` already produces for that case, instead of
    /// silently doing nothing (post-review finding #9).
    private var discoveredTextFilters: [TextFilterCommand] = []

    init(
        appCommands: [AppPaletteCommand] = AppPaletteCommand.standard,
        discoverTextFilters: @escaping () -> [TextFilterCommand] = { TextFilterCommandDiscovery.discoverCommands() },
        isAppCommandAvailable: @escaping (AppPaletteCommand) -> Bool = { _ in true },
        textFiltersAvailable: @escaping () -> Bool = { true }
    ) {
        self.appCommands = appCommands
        self.discoverTextFilters = discoverTextFilters
        self.isAppCommandAvailable = isAppCommandAvailable
        self.textFiltersAvailable = textFiltersAvailable
        refreshRows()
    }

    /// Re-scans for text filters and re-applies the current query. Intended
    /// to be called once per palette opening (its one call site is
    /// `CommandPaletteView.onAppear`) — a filesystem change is picked up
    /// the next time the palette opens, not on every keystroke while it is
    /// open, which previously synchronously rescanned the Commands
    /// directory on the main actor for every character typed
    /// (post-review finding #9).
    func refreshRows() {
        discoveredTextFilters = discoverTextFilters()
        applyFilter()
    }

    private func applyFilter() {
        rows = Self.filteredRows(
            query: query,
            appCommands: appCommands,
            isAppCommandAvailable: isAppCommandAvailable,
            textFilters: discoveredTextFilters,
            textFiltersAvailable: textFiltersAvailable()
        )
        selectedIndex = rows.isEmpty ? 0 : min(selectedIndex, rows.count - 1)
    }

    /// - Parameters:
    ///   - isAppCommandAvailable: filters out app commands that would be a
    ///     silent no-op in the current context — e.g. Save with nothing
    ///     dirty, Close Tab with no closable tab (post-review finding #8).
    ///   - textFiltersAvailable: `false` omits every discovered filter row
    ///     rather than showing commands that would do nothing for lack of
    ///     an active editor.
    static func filteredRows(
        query: String,
        appCommands: [AppPaletteCommand],
        isAppCommandAvailable: (AppPaletteCommand) -> Bool = { _ in true },
        textFilters: [TextFilterCommand],
        textFiltersAvailable: Bool = true
    ) -> [CommandPaletteRow] {
        let appRows = appCommands
            .filter(isAppCommandAvailable)
            .map { CommandPaletteRow(id: "app.\($0.id)", title: $0.title, kind: .appCommand) }
        let filterRows = textFiltersAvailable
            ? textFilters.map { CommandPaletteRow(id: "filter.\($0.id)", title: $0.name, kind: .textFilter) }
            : []
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
        originController: WindowController?,
        appHandler: (AppPaletteCommand, WindowCoordinator, WindowController?) -> Void,
        filterHandler: (TextFilterCommand) -> Void
    ) {
        guard let row = rows[safe: selectedIndex] else { return }
        switch row.kind {
        case .appCommand:
            guard let command = appCommands.first(where: { row.id == "app.\($0.id)" }) else { return }
            // Re-check availability now, not just at the last row rebuild
            // (post-review finding #5): the row the user is about to
            // invoke may have gone stale — its origin closed, or whatever
            // made it available stopped being true — in the interval
            // between that rebuild and this keystroke.
            guard isAppCommandAvailable(command) else { return }
            appHandler(command, coordinator, originController)
        case .textFilter:
            guard textFiltersAvailable() else { return }
            guard let command = discoveredTextFilters.first(where: { row.id == "filter.\($0.id)" }) else { return }
            filterHandler(command)
        }
    }
}
