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

    private let performQuery: @Sendable (String) async -> [IndexedPath]
    private var queryGeneration = 0

    /// `recentRelativePaths` implements issue #112's "Recent-file history
    /// feeds Quick Open ranking" (Slice 6c) — computed once by the caller
    /// (`QuickOpenPanel.init`, from `RecentFileDocuments.relativePaths(under:)`)
    /// at panel-open time, not re-read live for the panel's whole lifetime:
    /// a short-lived filtering session has no real staleness concern, and
    /// `WorkspaceFileIndex.query` itself already has no other reason to
    /// accept live, ongoing state.
    init(index: WorkspaceFileIndex, recentRelativePaths: Set<String> = []) {
        performQuery = { query in await index.query(query, limit: 100, recentRelativePaths: recentRelativePaths) }
    }

    /// Test-only seam: substitutes a caller-controlled query function for
    /// the real `WorkspaceFileIndex.query(_:limit:)` call, matching this
    /// project's established injectable-dependency shape for testing
    /// actor-based async work deterministically (`DocumentFileMonitor`'s
    /// injectable `sleeper`/`prober`/`watcher`, `WorkspaceFileIndex`'s own
    /// injectable `walk`). Needed because `WorkspaceFileIndex` is a single
    /// actor whose calls are always processed in the order they're
    /// submitted — two real queries issued back to back always COMPLETE in
    /// that same order too, so a test built only on the real actor cannot
    /// distinguish "the generation guard correctly discarded a late,
    /// stale result" from "the two queries just happened to finish in
    /// submission order anyway" (a hostile review of this exact slice
    /// proved this empirically: deleting the generation guard entirely
    /// still left every existing test passing). This seam lets a test
    /// force the actual inversion the guard exists to handle — a newer
    /// query's result committed before an older, now-stale query's
    /// late-arriving one — via controlled continuations.
    init(performQuery: @escaping @Sendable (String) async -> [IndexedPath]) {
        self.performQuery = performQuery
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
            let matches = await performQuery(currentQuery)
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
