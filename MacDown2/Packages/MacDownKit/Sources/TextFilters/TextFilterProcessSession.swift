import Darwin
import Foundation

/// Runs one text-filter process to completion, bounded by
/// `TextFilterRunner.Limits`, without blocking the awaiting task's thread
/// on raw pipe I/O (epic-14-implementation.md §8, §10).
///
/// `@unchecked Sendable`: `Pipe`/`FileHandle` predate Swift concurrency's
/// `Sendable` audits. `stdoutBuffer`/`stderrBuffer` are only ever touched
/// while holding `lock`; the terminal-verdict state lives in
/// `TextFilterTerminalState`, which owns its own synchronization. One
/// instance runs exactly one process; it is not reused.
///
/// ## Process-lifetime architecture (second and third adversarial passes)
///
/// The invocation is bounded as a **process group** — the one interpreter
/// MacDown directly launches, plus any live descendant still inside that
/// same group when this session contains it. That is a real, non-trivial
/// safety property (it defeats a plain backgrounded `&` job or an ordinary
/// pipeline stage that outlives the shell that started it), but it is
/// **not** "every descendant process, however deeply nested or regrouped"
/// — a descendant that calls `setpgid`/`setsid` to leave the group can
/// escape it. E14's contract is containment of the invocation's initial
/// process group; a trusted local script deliberately re-grouping itself
/// is outside that contract (third-adversarial-pass finding #7). A
/// successful result requires:
///
///   no forced verdict AND direct child exited AND stdout real EOF AND stderr real EOF
///
/// never weaker than that, and — critically — **never satisfied by an EOF
/// this session itself caused by forcibly killing a still-producing
/// process**. If the direct child exits but a descendant is still holding
/// a pipe open, `observeExitAndDrainage()` commits a fail-closed
/// `.incompleteOutput` verdict *before* containing the group, not after:
/// killing the group is guaranteed to make any remaining writer's fd
/// close and its reader observe "real" EOF, and that EOF must never be
/// able to retroactively turn a deliberately-killed partial stream into a
/// successful document replacement (third-adversarial-pass finding #1,
/// on the second remediation's own contain-then-maybe-still-succeed
/// ordering). Fabricating EOF via a timer, which is what the *first*
/// remediation did, is a different and already-fixed bug — this is about
/// a timer-triggered *action* being able to launder its own side effect
/// into a success fact after the fact.
///
/// `TextFilterTerminalState` commits its verdict exactly once; a watchdog
/// or cancellation racing in after a normal completion has already
/// committed cannot rewrite it (finding #3), and `finalize()` — not the
/// verdict itself — is responsible for actually containing the process
/// group and confirming its death before turning a forced verdict into the
/// corresponding thrown error (finding #2's confirmation-not-discarded
/// requirement). `TextFilterProcessGroup` never reaps its group leader
/// until this session is completely done needing to address the group by
/// its pid/pgid number, so that number can never be reused by an
/// unrelated process while this session might still signal it
/// (third-adversarial-pass finding #2).
final class TextFilterProcessSession: @unchecked Sendable {
    /// Caps how much stderr this session retains for an error message —
    /// independent of `maxOutputBytes`, since stderr is only ever used for
    /// a human-readable diagnostic, never placed in the document.
    private static let maxStderrBytes = 64 * 1024

    /// How long the direct child's exit is allowed to sit without real EOF
    /// on both streams before this session assumes something else is
    /// holding a pipe open and actively contains the process group to
    /// force it (finding #1). Ordinary pipelines/redirections never hit
    /// this: their stages are already dead (and their fds already closed)
    /// by the time the shell itself exits.
    private static let drainGracePeriod = Duration.milliseconds(500)

    /// Bounds how long a graceful `SIGTERM` is given to take effect before
    /// escalating to `SIGKILL`, and how long `SIGKILL` is given to be
    /// reaped, in `containGroup()`.
    private static let terminationGracePeriod = Duration.milliseconds(500)

    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let processGroup = TextFilterProcessGroup()
    private let terminalState = TextFilterTerminalState()

    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    private let maxOutputBytes: Int

    init(maxOutputBytes: Int) {
        self.maxOutputBytes = maxOutputBytes
    }

    /// Launches `command` with `input` on stdin and `context`'s working
    /// directory/environment, waits up to `timeout`, and returns decoded
    /// stdout — or throws the specific `TextFilterError` for whatever went
    /// wrong. Cooperatively cancellable: cancelling the calling `Task`
    /// terminates the live process group rather than abandoning it.
    func run(
        command: TextFilterCommand,
        input: String,
        context: TextFilterLaunchContext,
        timeout: Duration
    ) async throws -> String {
        // Reap the group leader only once this whole invocation is
        // completely done needing to address it by pid/pgid — on every
        // exit path, success or throw (third-adversarial-pass finding
        // #2's identity-safety requirement; see `TextFilterProcessGroup`'s
        // doc comment).
        defer { processGroup.reapLeader() }

        installReadabilityHandlers()

        do {
            try processGroup.spawn(
                executableURL: command.executableURL,
                workingDirectoryURL: context.workingDirectoryURL,
                environment: context.environment,
                pipes: TextFilterProcessGroup.StandardStreamPipes(
                    stdin: stdinPipe,
                    stdout: stdoutPipe,
                    stderr: stderrPipe
                )
            )
        } catch {
            teardownHandlers()
            throw TextFilterError.launchFailed(underlying: "\(error)")
        }

        // A script that never reads stdin (or exits before doing so) makes
        // writing to its pipe raise SIGPIPE. This applies Darwin's
        // descriptor-scoped `F_SETNOSIGPIPE` to just this pipe's write end
        // instead of MacDown's earlier `signal(SIGPIPE, SIG_IGN)`, which
        // mutated the whole app's signal disposition for its entire
        // remaining lifetime after the first filter ever ran and never
        // restored it (third-adversarial-pass finding #8). A failed write
        // still returns `EPIPE` rather than raising a signal either way —
        // only the blast radius changes.
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        // The child now owns dup'd copies of the ends it needs; MacDown's
        // own copies of the *other* ends must close now, or this process
        // itself becomes an extra writer/reader that can prevent EOF.
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        observeExitAndDrainage()
        writeInputAndCloseStdin(input)

        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            terminalState.requestVerdict(.timedOut)
        }

        let verdict = await withTaskCancellationHandler {
            await terminalState.wait()
        } onCancel: {
            terminalState.requestVerdict(.cancelled)
        }
        watchdog.cancel()

        teardownHandlers()
        return try await finalize(verdict)
    }

    // MARK: - Exit + drainage orchestration

    /// Watches for the direct child's exit and, if real EOF has not
    /// already arrived on both streams by then, gives it one bounded grace
    /// period before committing a fail-closed verdict and containing the
    /// process group to force real EOF. This is the one place a "timer"
    /// appears in the whole design, and its job is strictly to trigger a
    /// real action — never to fabricate a fact.
    ///
    /// The verdict commits **before** `finalize()`'s containment call
    /// (via `requireContainment()`), not after (third-adversarial-pass
    /// finding #1): containing the group is guaranteed to close any
    /// remaining writer's fd and produce real stdout/stderr EOF, and
    /// `TextFilterTerminalState`'s one-shot commit gate (finding #3) is
    /// what actually makes that EOF unable to retroactively satisfy
    /// `.exited` — but only if something has already claimed the verdict
    /// before that EOF can arrive. Requesting `.incompleteOutput` here,
    /// then containing, is that ordering; containing first and requesting
    /// only if containment failed (the second remediation's shape) leaves
    /// exactly the window a still-producing killed descendant needs to
    /// turn its partial output into a false "success".
    private func observeExitAndDrainage() {
        Task {
            let status = await processGroup.waitForExit()
            terminalState.recordChildExited(status)
            guard terminalState.committedVerdict == nil else { return }

            try? await Task.sleep(for: Self.drainGracePeriod)
            guard terminalState.committedVerdict == nil else { return }

            // Something is still holding a pipe open past the direct
            // child's own exit. Commit fail-closed now, before this
            // session ever sends a signal — see the doc comment above for
            // why the order matters. `finalize()` performs the actual
            // containment for every non-`.exited` verdict via
            // `requireContainment()`, so this Task's job ends at the
            // commit; it does not need to contain the group itself too.
            terminalState.requestVerdict(.incompleteOutput)
        }
    }

    // MARK: - Verdict -> result

    private func finalize(_ verdict: TextFilterTerminalState.Verdict) async throws -> String {
        switch verdict {
        case let .exited(status):
            // Even a clean, fully-drained exit can leave a residual
            // descendant behind — one that closed its inherited stdio
            // before detaching, so it never affected EOF at all. Sweep for
            // that before declaring success: "no filter-owned process
            // left running" applies to normal completion too, not only to
            // forced shutdowns.
            if processGroup.groupHasLiveMembers() {
                try await requireContainment()
            }
            return try decodeSuccess(status: status)
        case .timedOut:
            try await requireContainment()
            throw TextFilterError.timedOut
        case .cancelled:
            try await requireContainment()
            throw TextFilterError.cancelled
        case .oversized:
            try await requireContainment()
            throw TextFilterError.outputTooLarge
        case .incompleteOutput:
            // Containment already ran once to reach this verdict; verify
            // again rather than assuming it is still true.
            try await requireContainment()
            throw TextFilterError.outputIncomplete
        }
    }

    /// Confirms the process group is fully contained, or fails closed with
    /// a distinct error rather than silently proceeding as if it were
    /// (second-adversarial-pass finding #2) — factored out of `finalize`
    /// so its `switch` stays under the project's cyclomatic-complexity
    /// budget.
    private func requireContainment() async throws {
        guard await containGroup() else { throw TextFilterError.terminationUnconfirmed }
    }

    private func decodeSuccess(status: Int32) throws -> String {
        let (stdout, stderrData) = snapshotBuffers()
        guard status == 0 else {
            // Lossy decode: a diagnostic truncated at an arbitrary byte
            // boundary may end mid-UTF-8-sequence. Preserving the valid
            // prefix is more useful than discarding the whole message, so
            // this deliberately does not use the failable
            // `String(bytes:encoding:)` the lint rule below otherwise
            // prefers.
            // swiftlint:disable:next optional_data_string_conversion
            let stderrText = String(decoding: stderrData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TextFilterError.nonZeroExit(code: status, stderr: stderrText)
        }
        guard let text = String(bytes: stdout, encoding: .utf8) else {
            throw TextFilterError.outputNotDecodable
        }
        return text
    }

    private func snapshotBuffers() -> (stdout: Data, stderr: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (stdoutBuffer, stderrBuffer)
    }

    // MARK: - Process-group containment (finding #2)

    /// Terminates every process still in the filter's process group —
    /// graceful `SIGTERM` first, escalating to `SIGKILL` if anything
    /// ignored it — and returns only once confirmed empty (or was already
    /// empty). The result is never discarded by a caller: every path that
    /// calls this decides between the intended error and
    /// `.terminationUnconfirmed` based on what it returns.
    private func containGroup() async -> Bool {
        guard processGroup.groupHasLiveMembers() else { return true }
        processGroup.terminateGroup(SIGTERM)
        if await waitForGroupExit(timeout: Self.terminationGracePeriod) {
            return true
        }
        processGroup.terminateGroup(SIGKILL)
        return await waitForGroupExit(timeout: Self.terminationGracePeriod)
    }

    private func waitForGroupExit(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while processGroup.groupHasLiveMembers() {
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
            terminalState.recordStdoutEOF()
            return
        }
        lock.lock()
        // Once a verdict has committed, further bytes are discarded rather
        // than grown without bound, and there is no further need for this
        // handler to keep firing.
        guard terminalState.committedVerdict == nil else {
            lock.unlock()
            handle.readabilityHandler = nil
            return
        }
        stdoutBuffer.append(chunk)
        let overflowed = stdoutBuffer.count > maxOutputBytes
        lock.unlock()
        if overflowed {
            terminalState.requestVerdict(.oversized)
        }
    }

    private func handleStderr(_ chunk: Data, handle: FileHandle) {
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            terminalState.recordStderrEOF()
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
