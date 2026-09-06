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
final class TextFilterProcessSession: @unchecked Sendable {
    private enum Outcome {
        case exited(Int32)
        case timedOut
        case cancelled
        case oversized
    }

    /// Caps how much stderr this session retains for an error message —
    /// independent of `maxOutputBytes`, since stderr is only ever used for
    /// a human-readable diagnostic, never placed in the document.
    private static let maxStderrBytes = 64 * 1024

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Void, Never>?

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
            self?.resolve(.exited(proc.terminationStatus))
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
            self.resolve(.timedOut)
        }
        defer { watchdog.cancel() }

        await withTaskCancellationHandler {
            await waitForOutcome()
        } onCancel: {
            self.resolve(.cancelled)
        }

        teardownHandlers()
        return try finalize()
    }

    // MARK: - Completion

    /// Mirrors `PDFNavigationDelegate`'s watchdog-vs-continuation race
    /// (epic-14-implementation.md §8): only the *first* call to `resolve`
    /// after this wins, exactly like that delegate's `resume` guard.
    private func waitForOutcome() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if outcome != nil {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func resolve(_ newOutcome: Outcome) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = newOutcome
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }

    private func finalize() throws -> String {
        lock.lock()
        let resolvedOutcome = outcome
        let stdout = stdoutBuffer
        let stderrData = stderrBuffer
        lock.unlock()

        switch resolvedOutcome {
        case let .exited(status):
            guard status == 0 else {
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw TextFilterError.nonZeroExit(code: status, stderr: stderrText)
            }
            guard let text = String(data: stdout, encoding: .utf8) else {
                throw TextFilterError.outputNotDecodable
            }
            return text
        case .timedOut:
            terminateIfRunning()
            throw TextFilterError.timedOut
        case .cancelled:
            terminateIfRunning()
            throw TextFilterError.cancelled
        case .oversized:
            terminateIfRunning()
            throw TextFilterError.outputTooLarge
        case nil:
            // Unreachable: `waitForOutcome` never returns before `resolve`
            // has set `outcome`. Fails closed rather than force-unwrapping.
            throw TextFilterError.launchFailed(underlying: "the command finished with no recorded outcome")
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
            return
        }
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        stdoutBuffer.append(chunk)
        let overflowed = stdoutBuffer.count > maxOutputBytes
        lock.unlock()
        if overflowed {
            resolve(.oversized)
        }
    }

    private func handleStderr(_ chunk: Data, handle: FileHandle) {
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            return
        }
        lock.lock()
        if stderrBuffer.count < Self.maxStderrBytes {
            stderrBuffer.append(chunk)
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

    private func terminateIfRunning() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
