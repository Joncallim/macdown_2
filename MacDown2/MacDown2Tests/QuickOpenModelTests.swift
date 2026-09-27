import Foundation
@testable import MacDown2
import Testing
import TextSearch

/// EPIC-22 §6.15, Slice 6b — `QuickOpenModel`'s own pure query/selection
/// logic, mirroring `CommandPaletteModelTests`' own separation of model
/// tests from panel/view presentation. Uses a real, small temp directory
/// tree and `WorkspaceFileIndex`'s own public `rebuild(root:)` rather than
/// its package-internal `seedForTesting` seam (that seam is reserved for
/// `TextSearchTests`' own 100k-path performance test, in the same module as
/// `WorkspaceFileIndex` itself; a real small tree is both simpler here and
/// exercises the actual end-to-end `rebuild` → `query` path).
@Suite("QuickOpenModel")
@MainActor
struct QuickOpenModelTests {
    private final class TempTree {
        let root: URL

        init(_ files: [String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for relativePath in files {
                let url = root.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data().write(to: url)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func refreshWithNoQueryShowsIndexedFiles() async throws {
        let tree = try TempTree(["a.md", "b.swift"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.refresh()
        await waitUntil { model.results.count == 2 }

        #expect(Set(model.results.map(\.relativePath)) == ["a.md", "b.swift"])
    }

    @Test func queryFuzzyFiltersTheIndexedFiles() async throws {
        let tree = try TempTree(["WindowCoordinator.swift", "unrelated.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "wico"
        await waitUntil { model.results.count == 1 }

        #expect(model.results.first?.relativePath == "WindowCoordinator.swift")
    }

    @Test func rapidTypingDiscardsSupersededQueryResults() async throws {
        // Mirrors `EditorFindModel`'s own query-generation-counter
        // discipline (§8): a slower, now-superseded query's result must
        // never overwrite a newer query's already-committed one.
        let tree = try TempTree(["apple.txt", "banana.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "app"
        model.query = "ban"
        await waitUntil { model.results.count == 1 }

        #expect(model.results.first?.relativePath == "banana.txt")
    }

    @Test func moveSelectionWrapsAroundInBothDirections() async throws {
        let tree = try TempTree(["a.txt", "b.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)
        model.refresh()
        await waitUntil { model.results.count == 2 }
        #expect(model.selectedIndex == 0)

        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func moveSelectionOnAnEmptyResultListDoesNothing() async throws {
        let tree = try TempTree(["a.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "nonexistent"
        await waitUntil { model.results.isEmpty && !model.isSearching }

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func selectedResultReflectsTheCurrentSelectionIndex() async throws {
        let tree = try TempTree(["a.txt", "b.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)
        model.refresh()
        await waitUntil { model.results.count == 2 }

        model.moveSelection(by: 1)

        #expect(model.selectedResult?.relativePath == model.results[1].relativePath)
    }
}

/// A real wall-clock deadline, not a fixed iteration/yield-count budget —
/// same shape as `DocumentFileMonitorTests.swift`'s own `waitUntil` helper,
/// needed here because `QuickOpenModel.scheduleQuery()` resolves
/// asynchronously against the `WorkspaceFileIndex` actor. The condition is
/// `@MainActor`, not a plain `@Sendable` async closure, because
/// `QuickOpenModel` is a `@MainActor` class (its properties need actor
/// isolation to read, not an `await` on the class itself the way an actor's
/// properties would).
@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor @Sendable () -> Bool,
    timeout: Duration = .seconds(5)
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for QuickOpenModel to settle")
}
