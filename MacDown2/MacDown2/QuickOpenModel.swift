import Observation
import TextSearch

/// Pure query/selection logic for Quick Open (EPIC-22 §6.15, Slice 6b),
/// kept free of any AppKit/SwiftUI presentation so it is directly testable
/// without presenting UI — mirrors `CommandPaletteModel`'s same separation.
///
/// Unlike `CommandPaletteModel`'s `applyFilter()`, which is synchronous,
/// pure in-memory filtering, `WorkspaceFileIndex.query(_:limit:)` is an
/// actor call: querying it is `async`, so `query`'s own `didSet` cannot
/// filter synchronously the way the palette's does. Each edit spawns a new
/// `Task` and bumps `queryGeneration`, discarding any now-superseded
/// in-flight call's result — the same query-generation-counter discipline
/// `EditorFindModel.updateMatches` already established for exactly this
/// shape of problem (§8).
@MainActor
@Observable
final class QuickOpenModel {
    var query = "" {
        didSet { scheduleQuery() }
    }

    private(set) var results: [IndexedPath] = []
    private(set) var selectedIndex = 0
    private(set) var isSearching = false

    private let index: WorkspaceFileIndex
    private var queryGeneration = 0

    init(index: WorkspaceFileIndex) {
        self.index = index
    }

    /// Runs the current query once against the index. Intended to be called
    /// once per panel opening (its one call site is `QuickOpenView.onAppear`)
    /// — matching `CommandPaletteModel.refreshRows()`'s own "one real scan
    /// per opening, not one per keystroke" discipline — so the panel shows
    /// an initial result set (an empty query returns the index's own
    /// front-of-snapshot files, per `WorkspaceFileIndex.query`'s own
    /// documented empty-query behavior) the instant it appears.
    func refresh() {
        scheduleQuery()
    }

    private func scheduleQuery() {
        queryGeneration += 1
        let generation = queryGeneration
        let currentQuery = query
        isSearching = true
        Task {
            let matches = await index.query(currentQuery, limit: 100)
            guard generation == queryGeneration else { return } // superseded by a newer query
            results = matches
            selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
            isSearching = false
        }
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    var selectedResult: IndexedPath? {
        results[safe: selectedIndex]
    }
}
