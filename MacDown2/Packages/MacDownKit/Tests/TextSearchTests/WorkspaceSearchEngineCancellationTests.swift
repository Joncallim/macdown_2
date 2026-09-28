import FileCore
import Foundation
import Testing
@testable import TextSearch

/// Split out of `WorkspaceSearchEngineTests.swift` (SwiftLint's
/// `type_body_length` limit) — everything here concerns the engine's
/// safety properties under cancellation, permission failure, and symlink
/// loops, as opposed to that file's own core streaming/bounding/filter
/// behavior. Shares `WorkspaceSearchEngineTempTree`, `runFolderSearch`, and
/// `WorkspaceSearchEngineResultsBox` from that file (same module).
@Suite("WorkspaceSearchEngine cancellation and safety")
struct WorkspaceSearchEngineCancellationTests {
    // MARK: - Symlink loops (provenance: the loop guard itself lives in

    // `DirectoryWalker`, already proven not to hang by
    // `WorkspaceFileIndexTests.symlinkLoopDoesNotHang` -- this proves
    // `WorkspaceSearchEngine` genuinely inherits that guard end-to-end,
    // rather than re-deriving or duplicating it.)

    @Test func searchingAWorkspaceContainingASymlinkLoopCompletesAndFindsTheRealFile() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("real.txt", text: "needle")
        let looped = tree.root.appendingPathComponent("looped", isDirectory: true)
        try FileManager.default.createDirectory(at: looped, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: looped.appendingPathComponent("self"),
            withDestinationURL: looped
        )
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "needle")

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(results.map(\.relativePath) == ["real.txt"])
    }

    // MARK: - Permission failures (a deterministic read seam, not chmod's

    // own platform/sandbox-dependent timing -- a sandboxed test runner, or
    // running as root, can silently ignore permission bits entirely).

    @Test func aSimulatedPermissionFailureIsSkippedAndCountedDeterministically() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("readable.txt", text: "needle")
        try tree.write("locked.txt", text: "needle")
        let index = await tree.makeIndex()

        let seams = WorkspaceSearchEngine.TestSeams(readSnapshot: { root, path in
            guard path.relativePath != "locked.txt" else { return nil }
            return try? FileStore().readSnapshot(from: root.appendingPathComponent(path.relativePath))
        })
        let engine = WorkspaceSearchEngine(seams: seams)
        let box = WorkspaceSearchEngineResultsBox()
        let outcome = await engine.search(
            root: tree.root,
            index: index,
            query: "needle",
            options: SearchOptions()
        ) { match in await box.append(match) }

        guard case let .completed(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(filesSkipped == 1, "a permission failure must be skipped and counted, never crash or vanish silently")
        #expect(matchCount == 1)
        #expect(await box.all.map(\.relativePath) == ["readable.txt"])
    }

    // MARK: - Cancellation

    @Test func cancellingBeforeTheSearchStartsReturnsCancelledWithoutStreamingAnyResult() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        for fileIndex in 0 ..< 5 {
            try tree.write("file\(fileIndex).txt", text: "needle")
        }
        let index = await tree.makeIndex()

        // A naive "call `.cancel()` right after creating the `Task`" was
        // found, empirically, to race `search`'s own loop: 2 of 200 files
        // were sometimes already searched before the cancellation flag was
        // observed. `beforeEachFile` gives this test a real, deterministic
        // pause point instead of hoping to win that race.
        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(beforeEachFile: { await gate.waitUntilReleased() }))
        let box = WorkspaceSearchEngineResultsBox()
        let task = Task {
            await engine.search(root: tree.root, index: index, query: "needle", options: SearchOptions()) { match in
                await box.append(match)
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        let collected = await box.all
        #expect(collected.isEmpty, "a search cancelled before its first file was released must never stream a result")
    }

    /// Closes the gap an independent review found in the original
    /// implementation: it only checked `Task.isCancelled` once per file,
    /// BEFORE that file was read. A cancellation landing while a (possibly
    /// slow) file's matches are being computed, or while its result is
    /// being published, could still let that one extra result through and
    /// turn what should be `.cancelled` into `.completed`/`.truncated`.
    /// `afterMatchingFile` gives this test a real pause point exactly where
    /// that gap was: after a file's matches are computed, before they are
    /// published — a naive "cancel before the first file" test (above)
    /// could never have caught this, since it never lets any file's
    /// matching actually run.
    @Test func cancellingAfterAFilesMatchesAreComputedDiscardsThatFilesResult() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle")
        try tree.write("b.txt", text: "needle")
        let index = await tree.makeIndex()

        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(afterMatchingFile: { await gate.waitUntilReleased() }))
        let box = WorkspaceSearchEngineResultsBox()
        let task = Task {
            await engine.search(root: tree.root, index: index, query: "needle", options: SearchOptions()) { match in
                await box.append(match)
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(
            await box.all.isEmpty,
            "the first file's already-computed match must never be published once cancellation is discovered"
        )
    }

    /// EPIC-22 §6.16 keeps the generation-counter/workspace-root identity
    /// itself as 7b's own UI-layer responsibility — `WorkspaceSearchEngine`
    /// has no notion of "the current root" to compare against. Root-change
    /// safety therefore reduces entirely to cancellation being watertight
    /// even after a file's matches are already computed (the SAME guarantee
    /// `cancellingAfterAFilesMatchesAreComputedDiscardsThatFilesResult`
    /// proves generically); this test exercises that guarantee against the
    /// specific scenario issue #112 actually names — the workspace root
    /// changing mid-search — and additionally proves the engine carries no
    /// leftover state across calls: a fresh search against the NEW root,
    /// after the old one was cancelled, completes normally.
    @Test func rootReplacementDuringSearchNeverPublishesStaleResultsFromTheAbandonedRoot() async throws {
        let oldTree = try WorkspaceSearchEngineTempTree()
        try oldTree.write("old-a.txt", text: "needle")
        try oldTree.write("old-b.txt", text: "needle")
        let oldIndex = await oldTree.makeIndex()

        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(afterMatchingFile: { await gate.waitUntilReleased() }))
        let box = WorkspaceSearchEngineResultsBox()
        let task = Task {
            await engine.search(
                root: oldTree.root,
                index: oldIndex,
                query: "needle",
                options: SearchOptions()
            ) { match in await box.append(match) }
        }
        await gate.waitUntilPaused()
        // Simulates the caller's own generation-counter reaction (§6.16):
        // the workspace root changed underneath the in-flight search, so
        // the caller cancels it.
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(
            await box.all.isEmpty,
            "a search abandoned by a root change must never publish a result from the old root"
        )

        // The engine carries no per-search state of its own: a fresh search
        // against the NEW root works normally.
        let newTree = try WorkspaceSearchEngineTempTree()
        try newTree.write("new.txt", text: "needle")
        let newIndex = await newTree.makeIndex()
        let (newOutcome, newResults) = await runFolderSearch(root: newTree.root, index: newIndex, query: "needle")
        #expect(newOutcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(newResults.map(\.relativePath) == ["new.txt"])
    }

    /// Blocks the engine's own loop at a named seam until the test
    /// explicitly releases it, so a test can cancel the surrounding `Task`
    /// at a known, real pause point rather than racing a hopeful
    /// "cancel immediately after creation" against the loop's own
    /// scheduling. Reused for both `beforeEachFile` and `afterMatchingFile`
    /// pause points — the gate itself doesn't care which seam calls it.
    private actor PauseGate {
        private var isPaused = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

        func waitUntilReleased() async {
            isPaused = true
            for continuation in pausedContinuations {
                continuation.resume()
            }
            pausedContinuations.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitUntilPaused() async {
            if isPaused {
                return
            }
            await withCheckedContinuation { pausedContinuations.append($0) }
        }

        func release() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }
}
