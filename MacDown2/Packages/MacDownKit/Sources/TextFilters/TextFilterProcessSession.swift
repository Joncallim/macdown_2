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
/// ## Process-lifetime architecture (second through fourth adversarial passes)
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
/// is outside that contract. A successful result requires:
///
///   no forced verdict AND direct child exited AND stdout real EOF AND stderr real EOF
///
/// never weaker than that, and never satisfied by EOF this session itself
/// caused by forcibly killing a still-producing process. If the direct
/// child exits but a descendant is still holding a pipe open,
/// `observeExitAndDrainage()` commits a fail-closed `.incompleteOutput`
/// verdict before containment can create EOF as a side effect.
///
/// Fourth-pass hardening closes two additional cross-lock failure modes:
/// stdout-cap admission now commits `.oversized` under the *same terminal
/// lock* that can commit `.exited`, and process-group membership inspection
/// is tri-state (`empty`/`live`/`unconfirmed`) so a failed
/// `sysctl(KERN_PROC_PGRP)` query can never be mistaken for confirmed
/// emptiness.
final class TextFilterProcessSession: @unchecked Sendable {
    private static let maxStderrBytes = 64 * 1024
    private static let drainGracePeriod = Duration.milliseconds(500)
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
    /// Deterministic test seam for the fail-closed membership branch. Real
    /// runs leave this `nil` and use the Darwin process-table query.
    private let membershipStateOverride: (() -> TextFilterProcessGroup.MembershipState)?

    init(
        maxOutputBytes: Int,
        membershipStateOverride: (() -> TextFilterProcessGroup.MembershipState)? = nil
    ) {
        self.maxOutputBytes = maxOutputBytes
        self.membershipStateOverride = membershipStateOverride
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
        // exit path, success or throw.
        defer { processGroup.reapLeader() }

        installReadabilityHandlers()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(
            stdin: stdinPipe,
            stdout: stdoutPipe,
            stderr: stderrPipe
        )

        do {
            // Configure the parent writer before any child exists. Ignoring
            // a failed F_SETNOSIGPIPE would leave the entire MacDown process
            // exposed to SIGPIPE when a command exits without reading stdin.
            try processGroup.configureParentStdinWriteDescriptor(pipes)
            try processGroup.spawn(
                executableURL: command.executableURL,
                workingDirectoryURL: context.workingDirectoryURL,
                environment: context.environment,
                pipes: pipes
            )
        } catch {
            teardownHandlers()
            throw TextFilterError.launchFailed(underlying: "\(error)")
        }

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
    /// period before committing a fail-closed verdict. `finalize()` then
    /// contains the process group. The verdict commits before any signal is
    /// sent so signal-induced EOF can never be laundered into success.
    private func observeExitAndDrainage() {
        // Captures the two collaborators it needs rather than `self`: this
        // Task outlives `run()` whenever its drain-grace sleep is still
        // pending, and capturing the session would keep that whole object
        // — its pipes and output buffers included — alive for as long as
        // it did.
        Task { [processGroup, terminalState] in
            let status = await processGroup.waitForExit()
            terminalState.recordChildExited(status)
            guard terminalState.committedVerdict == nil else { return }

            try? await Task.sleep(for: Self.drainGracePeriod)
            guard terminalState.committedVerdict == nil else { return }

            terminalState.requestVerdict(.incompleteOutput)
        }
    }

    // MARK: - Verdict -> result

    private func finalize(_ verdict: TextFilterTerminalState.Verdict) async throws -> String {
        switch verdict {
        case let .exited(status):
            // Always pass through the same verified containment gate, even
            // for a clean exit. If the process-table query itself cannot be
            // confirmed, success is not allowed; if a residual descendant
            // remains, it is contained before the transform is accepted.
            try await requireContainment()
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
            try await requireContainment()
            throw TextFilterError.outputIncomplete
        }
    }

    /// Confirms the process group is fully contained, or fails closed with
    /// a distinct error rather than silently proceeding as if it were.
    private func requireContainment() async throws {
        guard await containGroup() else { throw TextFilterError.terminationUnconfirmed }
    }

    private func decodeSuccess(status: Int32) throws -> String {
        let (stdout, stderrData) = snapshotBuffers()
        guard status == 0 else {
            // Lossy decode: a diagnostic truncated at an arbitrary byte
            // boundary may end mid-UTF-8-sequence. Preserving the valid
            // prefix is more useful than discarding the whole message.
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

    // MARK: - Process-group containment

    /// Terminates every process still in the filter's initial process group
    /// and returns only once a process-table snapshot confirms no live
    /// member remains. `.unconfirmed` is intentionally treated as "not yet
    /// safe": the method may signal the identity-pinned group and retry, but
    /// it can never convert inspection failure into successful completion.
    private func containGroup() async -> Bool {
        switch currentMembershipState() {
        case .empty:
            return true
        case .live, .unconfirmed:
            break
        }

        // A signal that could not be sent at all (e.g. `EPERM`) is not
        // something to poll over: escalating would fail identically, and
        // the group would only be watched, never acted on. Fail closed.
        if case .failed = processGroup.terminateGroup(SIGTERM) {
            return false
        }
        if await waitForGroupExit(timeout: Self.terminationGracePeriod) {
            return true
        }
        if case .failed = processGroup.terminateGroup(SIGKILL) {
            return false
        }
        return await waitForGroupExit(timeout: Self.terminationGracePeriod)
    }

    private func waitForGroupExit(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if currentMembershipState() == .empty {
                return true
            }
            await Self.uninterruptiblePause(milliseconds: 20)
        }
        return currentMembershipState() == .empty
    }

    private func currentMembershipState() -> TextFilterProcessGroup.MembershipState {
        membershipStateOverride?() ?? processGroup.verifiedMembershipState()
    }

    /// A pause a cancelled task cannot skip. Deliberately **not**
    /// `Task.sleep`: the `.cancelled` verdict's containment by definition
    /// runs inside an already-cancelled task, where `Task.sleep` returns
    /// immediately — collapsing this 20 ms poll into a hot spin over a
    /// `sysctl` process-table enumeration for the whole grace period,
    /// twice, every time a window closes while a filter is running.
    private static func uninterruptiblePause(milliseconds: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
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

        // The output-cap decision and the terminal verdict are one atomic
        // operation. `processStdoutChunk` holds the terminal-state lock while
        // this closure checks/appends under the buffer lock, so exit+EOF can
        // neither commit success between the cap check and `.oversized` nor
        // snapshot a supposedly-complete buffer before an accepted chunk is
        // actually appended. The buffer itself also never grows past the cap.
        let disposition = terminalState.processStdoutChunk {
            lock.lock()
            defer { lock.unlock() }

            guard maxOutputBytes >= stdoutBuffer.count,
                  chunk.count <= maxOutputBytes - stdoutBuffer.count
            else {
                return true
            }
            stdoutBuffer.append(chunk)
            return false
        }

        if disposition != .accepted {
            handle.readabilityHandler = nil
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
