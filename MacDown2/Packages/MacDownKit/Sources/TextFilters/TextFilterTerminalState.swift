import Foundation

/// The one-shot terminal-state machine for a single text-filter process
/// invocation, deliberately free of any process/pipe I/O so hostile event
/// orderings can be driven directly in tests without spawning a real
/// process (second-adversarial-pass findings #1/#3).
///
/// **Finding #1** (a 500ms drain-grace timer could fabricate EOF and
/// return a truncated prefix as a successful result): a `.exited` verdict
/// — the only verdict that can produce successful output — commits **only**
/// when the direct child has exited *and* both stdout and stderr have
/// reached real, observed EOF (`recordChildExited`/`recordStdoutEOF`/
/// `recordStderrEOF`). Nothing in this type can fabricate an EOF fact;
/// `TextFilterProcessSession` is responsible for making EOF actually true
/// (by containing the process group) before ever calling these.
///
/// **Finding #3** (a late watchdog could rewrite an already-committed
/// normal completion): every verdict, forced or resolved, commits through
/// the same one-shot gate (`verdict == nil` checked and set atomically
/// under `lock`). Once any verdict commits, nothing recorded or requested
/// afterward can replace it — the previous implementation's `resumed` flag
/// only protected the `CheckedContinuation` from a double-resume; it did
/// not protect the verdict value itself from being overwritten between the
/// continuation resuming and `finalize()` later reading it.
final class TextFilterTerminalState: @unchecked Sendable {
    enum Verdict: Equatable {
        /// The direct child exited with `status`, and both stdout and
        /// stderr have reached real EOF. The only verdict `finalize()` can
        /// turn into successful output.
        case exited(Int32)
        case timedOut
        case cancelled
        case oversized
        /// The process group was terminated (finding #2's containment) but
        /// real EOF still could not be observed afterward — an anomaly,
        /// never silently treated as success (finding #1).
        case incompleteOutput
    }

    private let lock = NSLock()
    private var childExitStatus: Int32?
    private var stdoutEOF = false
    private var stderrEOF = false
    private var verdict: Verdict?
    private var continuation: CheckedContinuation<Verdict, Never>?

    /// The committed verdict, if any, without waiting. Lets a caller check
    /// "has this already resolved?" before doing further work (e.g. before
    /// starting a drain-grace timer that would be pointless if a forced
    /// verdict already won).
    var committedVerdict: Verdict? {
        lock.lock()
        defer { lock.unlock() }
        return verdict
    }

    /// Suspends until a verdict commits, then returns it. Safe to call
    /// before or after the verdict has already committed.
    func wait() async -> Verdict {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let verdict {
                lock.unlock()
                continuation.resume(returning: verdict)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    /// Records the direct child's exit status. Contributes toward — but
    /// does not by itself commit — an `.exited` verdict; that still needs
    /// both streams to have reached real EOF.
    func recordChildExited(_ status: Int32) {
        applyFactAndResume { self.childExitStatus = status }
    }

    func recordStdoutEOF() {
        applyFactAndResume { self.stdoutEOF = true }
    }

    func recordStderrEOF() {
        applyFactAndResume { self.stderrEOF = true }
    }

    /// Requests an externally-forced verdict (timeout/cancellation/
    /// oversized output/incomplete drain). Returns `true` only if this
    /// call is the one that actually committed it — the caller uses that
    /// to decide whether it owns triggering the corresponding one-time
    /// side effect (e.g. containing the process group), so two racing
    /// requests never both act on the same commit.
    @discardableResult
    func requestVerdict(_ requested: Verdict) -> Bool {
        lock.lock()
        guard verdict == nil else {
            lock.unlock()
            return false
        }
        verdict = requested
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: requested)
        return true
    }

    /// Applies one observed fact under `lock`, then — still one-shot —
    /// commits `.exited` if the accumulated facts now warrant it, and
    /// resumes any waiter outside the lock.
    private func applyFactAndResume(_ mutate: () -> Void) {
        lock.lock()
        mutate()
        guard verdict == nil, let childExitStatus, stdoutEOF, stderrEOF else {
            lock.unlock()
            return
        }
        let resolved = Verdict.exited(childExitStatus)
        verdict = resolved
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: resolved)
    }
}
