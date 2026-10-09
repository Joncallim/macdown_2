import Foundation

/// Shared, deterministic wait for a `SavePublicationBarrier` (or any other
/// continuation-backed test signal) with a generous wall-clock safety net —
/// not a fixed-iteration/yield-count budget.
///
/// This exists because three separate tests (`WorkspaceModelRecoveryTests`,
/// `WorkspaceModelFileTests`, `WorkspaceModelFileSaveAsTests`) each
/// reimplemented their own ad hoc wait for `barrier.hasArrived`, two of them
/// via `for _ in 0 ..< 200 { await Task.yield() }` — a busy-poll with NO
/// actual wall-clock guarantee: 200 yields can resolve near-instantly on an
/// idle machine (giving essentially no real margin) or fail to make any
/// meaningful scheduling progress at all under a contended CI runner,
/// producing a spurious "timed out" failure that has nothing to do with
/// correctness. `WorkspaceModelSaveQueueTests` had already independently
/// arrived at the right shape (a `TaskGroup` racing the real continuation
/// against a genuine multi-second `Task.sleep` deadline, with the timeout
/// used only as a safety net, never as the synchronization primitive
/// itself) — this promotes that one correct implementation to a shared
/// helper instead of leaving three divergent, two of them wrong, copies.
///
/// `SavePublicationBarrier.waitForFirstPublication()` is itself already a
/// real, continuation-based signal (resumed the instant `arriveAndWait()`
/// runs) — the fix here is purely "await that directly, wrapped in a
/// generous timeout," never re-deriving the signal via polling.
@discardableResult
func waitForSignal(
    timeout: Duration = .seconds(5),
    wait: @escaping @Sendable () async -> Bool,
    onTimeout: (@Sendable () -> Void)? = nil
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask { await wait() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let result = await group.next() ?? false
        if !result {
            onTimeout?()
        }
        group.cancelAll()
        return result
    }
}
