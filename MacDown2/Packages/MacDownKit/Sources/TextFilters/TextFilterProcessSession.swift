import Foundation

/// Runs one text-filter process to completion, bounded by
/// `TextFilterRunner.Limits`, without blocking the awaiting task's thread
/// on raw `Process`/`Pipe` I/O (epic-14-implementation.md §8, §10).
///
/// `@unchecked Sendable`: `Process`/`Pipe`/`FileHandle` predate Swift
/// concurrency's `Sendable` audits. Every mutable property is only ever
/// touched while holding `lock` — including from the readability handlers
/// and termination handler Foundation invokes on its own background
/// queues — so this class is the one place that owns that synchronization.
/// One instance runs exactly one process; it is not reused.
///
/// State machine (post-remediation review finding #2): a direct process
/// exiting does **not** by itself mean its output has been fully delivered
/// — Foundation's asynchronous `readabilityHandler` callbacks can still be
/// queued behind the termination callback, so treating exit as completion
/// let a zero-exit filter's stdout be silently truncated. Normal completion
/// now requires the process to have exited **and** both stdout and stderr
/// to have reached EOF. A forced outcome (timeout/cancellation/oversized
/// output) is allowed to short-circuit that wait, since its output is
/// discarded anyway, but once recorded it permanently dominates: a later
/// zero exit can no longer resurrect an already-oversized run (the other
/// half of finding #2).
final class TextFilterProcessSession: @unchecked Sendable {
    /// A terminal condition the runner forces rather than one the process
    /// reached on its own. Once set, this dominates the final result even
    /// if the process goes on to exit 0 — see the type's doc comment.
    private enum ForcedOutcome {
        case timedOut
        case cancelled
        case oversized
    }

    /// Caps how much stderr this session retains for an error message —
    /// independent of `maxOutputBytes`, since stderr is only ever used for
    /// a human-readable diagnostic, never placed in the document.
    private static let maxStderrBytes = 64 * 1024

    /// Bounds how long a graceful `SIGTERM` is given to take effect before
    /// escalating to `SIGKILL`, and how long `SIGKILL` is given to be
    /// reaped, in `confirmTermination()` (finding #4).
    private static let terminationGracePeriod = Duration.milliseconds(500)

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var stdoutDone = false
    private var stderrDone = false
    private var exitStatus: Int32?
    private var forcedOutcome: ForcedOutcome?
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false

    private let maxOutputBytes: Int

    init(maxOutputBytes: Int) {
        self.maxOutputBytes = maxOutputBytes
    }

    /// Launches `command` with `input` on stdin and `context`'s working
    /// directory/environment, waits up to `timeout`, and returns decoded
    /// stdout — or throws the specific `TextFilterError` for whatever went
    /// wrong. Cooperatively cancellable: cancelling the calling `Task`
    /// terminates the live process rather than abandoning it.
    func run(
        command: TextFilterCommand,
        input: String,
        context: TextFilterLaunchContext,
        timeout: Duration
    ) async throws -> String {
        // A script that never reads stdin (or exits before doing so) makes
        // writing to its pipe raise SIGPIPE, fatal to the whole app by
        // default. Ignoring it process-wide is the standard, harmless
        // mitigation for `Process`/`Pipe` use — idempotent, safe to call
        // on every run.
        signal(SIGPIPE, SIG_IGN)

        process.executableURL = command.executableURL
        process.arguments = []
        process.currentDirectoryURL = context.workingDirectoryURL
        process.environment = context.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        installReadabilityHandlers()
        process.terminationHandler = { [weak self] proc in
            self?.recordExit(proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            teardownHandlers()
            throw TextFilterError.launchFailed(underlying: error.localizedDescription)
        }

        writeInputAndCloseStdin(input)

        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.forceOutcome(.timedOut)
        }
        defer { watchdog.cancel() }

        await withTaskCancellationHandler {
            await waitForOutcome()
        } onCancel: {
            self.forceOutcome(.cancelled)
        }

        teardownHandlers()
        return try await finalize()
    }

    // MARK: - Completion

    /// Suspends until `readyToResumeLocked()` decides the run is over —
    /// either a forced outcome was recorded, or the process has exited and
    /// both pipes have reached EOF.
    private func waitForOutcome() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            self.continuation = continuation
            let toResume = readyToResumeLocked()
            lock.unlock()
            toResume?.resume()
        }
    }

    /// Must be called while holding `lock`. Returns the waiter's
    /// continuation exactly once, the moment the run's terminal state is
    /// fully known — never before, and never more than once.
    private func readyToResumeLocked() -> CheckedContinuation<Void, Never>? {
        guard !resumed, let pending = continuation else { return nil }
        let ready = forcedOutcome != nil || (exitStatus != nil && stdoutDone && stderrDone)
        guard ready else { return nil }
        resumed = true
        continuation = nil
        return pending
    }

    /// Records a forced terminal condition. The *first* one wins — once a
    /// timeout/cancellation/oversized verdict is recorded, a later exit
    /// status can no longer overwrite it, closing the race where a
    /// still-running process happens to exit 0 immediately after being
    /// asked to stop.
    private func forceOutcome(_ outcome: ForcedOutcome) {
        lock.lock()
        guard forcedOutcome == nil else {
            lock.unlock()
            return
        }
        forcedOutcome = outcome
        let toResume = readyToResumeLocked()
        lock.unlock()
        toResume?.resume()
    }

    private func recordExit(_ status: Int32) {
        lock.lock()
        exitStatus = status
        let stillDraining = !(stdoutDone && stderrDone)
        let toResume = readyToResumeLocked()
        lock.unlock()
        toResume?.resume()
        if stillDraining {
            scheduleDrainGracePeriod()
        }
    }

    /// Descendant-process-tree policy (post-review finding #4, documented
    /// rather than left implicit): only the *direct* child's own I/O is
    /// waited on. A shell idiom like `(sleep 5 &)` backgrounds a grandchild
    /// that inherits the stdout/stderr pipe's write end; that grandchild
    /// keeps the read end from ever seeing EOF for as long as it lives,
    /// which is unrelated to whether the direct child produced its output
    /// correctly. Requiring true EOF unconditionally (the fix for
    /// finding #2's truncation race) would otherwise make MacDown wait on —
    /// or misreport as timed out — a process it never spawned and holds no
    /// reference to. A bounded grace period after the direct child exits
    /// accepts whatever has been captured so far if the pipes are still
    /// open once it elapses, exactly mirroring `confirmTermination()`'s own
    /// grace-period-then-proceed shape.
    private func scheduleDrainGracePeriod() {
        Task {
            try? await Task.sleep(for: Self.terminationGracePeriod)
            self.forceDrainCompletion()
        }
    }

    private func forceDrainCompletion() {
        lock.lock()
        stdoutDone = true
        stderrDone = true
        let toResume = readyToResumeLocked()
        lock.unlock()
        toResume?.resume()
    }

    private struct FinalState {
        let forced: ForcedOutcome?
        let exit: Int32?
        let stdout: Data
        let stderr: Data
    }

    /// A snapshot of the terminal state, read under `lock`. Factored into a
    /// synchronous method because `NSLock.lock()`/`unlock()` are unavailable
    /// from `async` contexts (Swift 6 strict concurrency) — `finalize()`
    /// itself must be `async` to `await confirmTermination()`.
    private func snapshotFinalState() -> FinalState {
        lock.lock()
        defer { lock.unlock() }
        return FinalState(forced: forcedOutcome, exit: exitStatus, stdout: stdoutBuffer, stderr: stderrBuffer)
    }

    private func finalize() async throws -> String {
        let state = snapshotFinalState()

        if let forced = state.forced {
            // The process may still be alive (a forced outcome does not
            // wait for it to exit): confirm it is actually stopped before
            // reporting completion (finding #4), rather than merely having
            // sent a signal it might ignore.
            await confirmTermination()
            switch forced {
            case .timedOut:
                throw TextFilterError.timedOut
            case .cancelled:
                throw TextFilterError.cancelled
            case .oversized:
                throw TextFilterError.outputTooLarge
            }
        }

        guard let exit = state.exit else {
            // Unreachable: `waitForOutcome` never returns before either a
            // forced outcome or a real exit status is recorded. Fails
            // closed rather than force-unwrapping.
            throw TextFilterError.launchFailed(underlying: "the command finished with no recorded outcome")
        }
        guard exit == 0 else {
            // Lossy decode: a diagnostic truncated at an arbitrary byte
            // boundary may end mid-UTF-8-sequence. Preserving the valid
            // prefix is more useful than discarding the whole message, so
            // this deliberately does not use the failable
            // `String(bytes:encoding:)` the lint rule below otherwise
            // prefers (post-review finding #16).
            // swiftlint:disable:next optional_data_string_conversion
            let stderrText = String(decoding: state.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TextFilterError.nonZeroExit(code: exit, stderr: stderrText)
        }
        guard let text = String(bytes: state.stdout, encoding: .utf8) else {
            throw TextFilterError.outputNotDecodable
        }
        return text
    }

    // MARK: - Termination (finding #4)

    /// Only the direct child process's lifetime is guaranteed bounded by
    /// this method. A script that daemonizes a detached grandchild before
    /// responding to `SIGTERM`/`SIGKILL` can leave that grandchild running
    /// — this is an explicit, documented limitation (not a silent gap):
    /// text-filter commands are the user's own trusted local automation
    /// (epic-14-implementation.md §10), and `doesNotWaitOnAForkedGrandchildProcess`
    /// in `TextFilterRunnerTests` already codifies "MacDown only waits on
    /// the direct child" as the chosen policy.
    private func confirmTermination() async {
        guard process.isRunning else { return }
        process.terminate()
        if await waitUntilNotRunning(timeout: Self.terminationGracePeriod) {
            return
        }
        // The direct child ignored SIGTERM (e.g. `trap '' TERM`). Escalate
        // rather than reporting a stop that did not actually happen.
        kill(process.processIdentifier, SIGKILL)
        _ = await waitUntilNotRunning(timeout: Self.terminationGracePeriod)
    }

    private func waitUntilNotRunning(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    // MARK: - I/O

    private func installReadabilityHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleStdout(handle.availableData, handle: handle)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleStderr(handle.availableData, handle: handle)
        }
    }

    private func handleStdout(_ chunk: Data, handle: FileHandle) {
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            lock.lock()
            stdoutDone = true
            let toResume = readyToResumeLocked()
            lock.unlock()
            toResume?.resume()
            return
        }
        lock.lock()
        // Once a forced outcome has been recorded, further bytes are
        // discarded rather than grown without bound, and there is no
        // further need for this handler to keep firing.
        guard forcedOutcome == nil else {
            lock.unlock()
            handle.readabilityHandler = nil
            return
        }
        stdoutBuffer.append(chunk)
        if stdoutBuffer.count > maxOutputBytes {
            // Decided and recorded atomically in the same critical section
            // as the append that crossed the cap, so a termination handler
            // racing in on another queue cannot observe a state where the
            // buffer is over-cap but no outcome has been recorded yet
            // (the other half of finding #2).
            forcedOutcome = .oversized
        }
        let toResume = readyToResumeLocked()
        lock.unlock()
        toResume?.resume()
    }

    private func handleStderr(_ chunk: Data, handle: FileHandle) {
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            lock.lock()
            stderrDone = true
            let toResume = readyToResumeLocked()
            lock.unlock()
            toResume?.resume()
            return
        }
        lock.lock()
        let remaining = Self.maxStderrBytes - stderrBuffer.count
        if remaining > 0 {
            stderrBuffer.append(chunk.prefix(remaining))
        }
        lock.unlock()
    }

    private func teardownHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func writeInputAndCloseStdin(_ input: String) {
        let data = Data(input.utf8)
        let handle = stdinPipe.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            if !data.isEmpty {
                try? handle.write(contentsOf: data)
            }
            try? handle.close()
        }
    }
}
