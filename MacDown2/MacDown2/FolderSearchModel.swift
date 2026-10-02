import Foundation
import Observation
import TextSearch

/// Pure query/results logic for folder-wide search (EPIC-22 §6.16, Slice
/// 7b), kept free of any AppKit/SwiftUI presentation so it is directly
/// testable — mirrors `QuickOpenModel`'s own separation. One instance lives
/// for the lifetime of a window (`WindowController.folderSearchModel`),
/// the same way `workspaceFileIndex` does, rather than being recreated per
/// folder root — `setRoot(_:)` is called from the same place
/// `workspaceFileIndex.rebuild`/`.clear()` already are
/// (`WindowController+WorkspaceIndex.swift`).
///
/// Unlike `QuickOpenModel`'s single in-memory `WorkspaceFileIndex.query`
/// call, `WorkspaceSearchEngine.search` is a genuinely long-running,
/// streaming disk operation: a superseded search must not just have its
/// late RESULT discarded, it must be cancelled outright so it stops doing
/// real work. `generation` is bumped on every new query and on `setRoot`,
/// so a result that streams in after cancellation was requested — a real
/// race, since `Task.cancel()` and the engine's own next cooperative check
/// are never instantaneous — is discarded rather than appended, mirroring
/// `QuickOpenModel`'s own generation-guard discipline one layer further.
///
/// The injected `performSearch`'s `onMatch` stays `async`, not
/// fire-and-forget: awaiting the MainActor hop for each match (rather than
/// spawning a detached `Task` per match) is what preserves
/// `WorkspaceSearchEngine.search`'s own documented guarantee that it never
/// moves to the next file until the caller has fully processed the
/// current one. The `onMatch` closure literal passed at each call site is
/// itself annotated `@MainActor` (not just `async`): a plain `async`
/// closure touching this class's `@MainActor`-isolated stored properties
/// still needs an explicit hop, while a closure statically isolated to
/// `@MainActor` may read/write them directly and is still a valid
/// `@Sendable` value (a global-actor-isolated function is inherently safe
/// to hand across an isolation boundary, since invoking it always
/// re-enters that actor).
@MainActor
@Observable
final class FolderSearchModel {
    var query = "" {
        didSet { scheduleSearch() }
    }

    private(set) var results: [FolderSearchMatch] = []
    private(set) var isSearching = false
    private(set) var outcome: FolderSearchOutcome?
    private(set) var root: URL?
    /// The folder as the user opened it (a symlink path stays a symlink path),
    /// used to name files that are opened from results so they carry the same
    /// identity as the same file opened from the sidebar; `root` is the
    /// physical access root searches read through (#183 F19).
    private(set) var lexicalRoot: URL?

    /// Replace in Folder (Slice 7c) state. Stored here because `@Observable`
    /// requires stored properties in the class body; the behavior lives in
    /// `FolderSearchModel+Replace.swift`.
    var replacement = "" {
        didSet { replacementDidChange() }
    }

    var isReplaceVisible = false
    var isConfirmingReplace = false
    var excludedPaths: Set<String> = []
    var expandedPaths: Set<String> = []
    var previews: [String: ReplacementFilePreview] = [:]
    var isReplacing = false
    var replaceCompleted = 0
    var replaceTotal = 0
    var replaceSummary: FolderReplaceSummary?
    /// Consulted (on the main actor) immediately before each file is
    /// rewritten: a document open with unsaved edits must never be
    /// overwritten on disk. Assigned by `WindowController`, which knows the
    /// coordinator that can see every window's tabs.
    var hasUnsavedOpenDocument: @MainActor (URL) -> Bool = { _ in false }
    let performReplace: FolderReplaceRunner
    let performPreview: FolderReplacePreviewBuilder
    var replaceTask: Task<Void, Never>?
    /// Identifies the one Replace run allowed to publish; bumped whenever the
    /// run is retired (root change) so a late completion is discarded.
    var replaceGeneration = 0
    var previewGeneration = 0

    private let performSearch: @Sendable (
        URL,
        String,
        @escaping @Sendable (FolderSearchMatch) async -> Void
    ) async -> FolderSearchOutcome
    /// Coalesces rapid keystrokes into far fewer real `WorkspaceSearchEngine
    /// .search` calls — unlike `QuickOpenModel.scheduleQuery()`, which this
    /// class otherwise mirrors, each call here is genuine disk I/O and
    /// regex matching (per `WorkspaceSearchEngine.search`'s own doc
    /// comment, cancellation is only checked between/around files, never
    /// mid-file), not an in-memory scan — an independent review of this
    /// slice found that without a debounce, every keystroke still does at
    /// least one real file's worth of I/O and matching before its search is
    /// cancelled. `setRoot(_:)` re-runs the current query WITHOUT this
    /// debounce (`scheduleSearch(debounced: false)`), matching
    /// `QuickOpenModel.refresh()`'s own "one real scan per opening, not
    /// delayed like a keystroke" precedent — opening a folder is a discrete
    /// action, not a burst of rapid edits to coalesce.
    private let debounce: Duration
    private var generation = 0
    private var currentTask: Task<Void, Never>?

    init(
        index: WorkspaceFileIndex,
        filter: FolderSearchFilter = FolderSearchFilter(),
        debounce: Duration = .milliseconds(150)
    ) {
        let engine = WorkspaceSearchEngine()
        let replaceEngine = Self.makeReplaceEngine()
        performReplace = replaceEngine.run
        performPreview = replaceEngine.preview
        performSearch = { root, query, onMatch in
            await engine.search(
                root: root,
                index: index,
                query: query,
                options: SearchOptions(),
                filter: filter,
                onMatch: onMatch
            )
        }
        self.debounce = debounce
    }

    /// Test-only seam: substitutes a caller-controlled search function for
    /// the real `WorkspaceSearchEngine.search` call, matching this
    /// project's established injectable-dependency shape (`QuickOpenModel`'s
    /// own `init(performQuery:)`) for testing actor-based async streaming
    /// work deterministically. `debounce` defaults to zero here (not the
    /// production 150ms) so tests built directly on this seam do not need
    /// to account for a delay they are not testing.
    init(
        performSearch: @escaping @Sendable (
            URL,
            String,
            @escaping @Sendable (FolderSearchMatch) async -> Void
        ) async -> FolderSearchOutcome,
        debounce: Duration = .zero,
        performReplace: FolderReplaceRunner? = nil,
        performPreview: FolderReplacePreviewBuilder? = nil
    ) {
        self.performSearch = performSearch
        self.debounce = debounce
        let real = Self.makeReplaceEngine()
        self.performReplace = performReplace ?? real.run
        self.performPreview = performPreview ?? real.preview
    }

    /// Sets (or clears) the folder root this model searches, cancelling any
    /// in-flight search and re-running the current query text (if any)
    /// against the new root — mirrors `WorkspaceFileIndex.rebuild(root:)`'s
    /// own "a query made while switching still sees a consistent result,
    /// never a mix of old and new" discipline, applied to the model's own
    /// query/results pair instead of the index's own snapshot.
    func setRoot(_ root: URL?, lexicalRoot: URL? = nil) {
        if root != self.root {
            retireReplaceRun()
        }
        self.root = root
        self.lexicalRoot = root == nil ? nil : (lexicalRoot ?? root)
        scheduleSearch(debounced: false)
    }

    func scheduleSearch(debounced: Bool = true, keepingReplaceSummary: Bool = false) {
        generation += 1
        let thisGeneration = generation
        currentTask?.cancel()
        currentTask = nil
        results = []
        outcome = nil
        resetReplaceReview(keepingSummary: keepingReplaceSummary)

        let currentQuery = query
        guard let root, !currentQuery.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true

        currentTask = Task { [weak self] in
            guard let self else { return }
            if debounced, debounce > .zero {
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    return // cancelled during the debounce window
                }
                guard generation == thisGeneration else { return }
            }
            let searchOutcome = await performSearch(root, currentQuery) { @MainActor [weak self] match in
                guard let self, generation == thisGeneration else { return }
                results.append(match)
            }
            guard generation == thisGeneration else { return }
            outcome = searchOutcome
            isSearching = false
        }
    }
}
