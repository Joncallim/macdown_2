import Dispatch
import Foundation

/// Low-level process-group spawn/termination/existence mechanics, isolated
/// from `TextFilterProcessSession`'s I/O and verdict orchestration so each
/// can be reasoned about independently (second-adversarial-pass finding
/// #2).
///
/// `Foundation.Process` has no API to place a child into its own process
/// group **before** it execs. That containment has to be established
/// atomically as part of the spawn itself — a parent-side `setpgid` call
/// issued after `Process.run()` returns is already too late if the child
/// forks a grandchild in the window before the parent gets scheduled again,
/// and Foundation exposes no hook to run one in between. So this spawns via
/// `posix_spawn` directly with `POSIX_SPAWN_SETPGROUP`/`posix_spawnattr_setpgroup(_:0)`,
/// which the kernel applies before the child's first instruction executes.
///
/// Once spawned this way, the child's own pid **is** its process group id
/// (POSIX: `pgroup == 0` with `POSIX_SPAWN_SETPGROUP` means "become the
/// leader of a new group named after yourself"), so every method here
/// after `spawn()` addresses the whole group via `-pid`, not just the one
/// process MacDown directly launched.
final class TextFilterProcessGroup: @unchecked Sendable {
    enum SpawnError: Error, CustomStringConvertible {
        case posixError(Int32)

        var description: String {
            switch self {
            case let .posixError(code):
                String(cString: strerror(code))
            }
        }
    }

    /// Bundles the three standard-stream pipes so `spawn(executableURL:
    /// workingDirectoryURL:environment:pipes:)` stays within the
    /// project's function-parameter-count budget.
    struct StandardStreamPipes {
        let stdin: Pipe
        let stdout: Pipe
        let stderr: Pipe
    }

    private let lock = NSLock()
    private(set) var pid: pid_t?
    private var exitSource: DispatchSourceProcess?
    private var exitStatus: Int32?
    private var exitContinuation: CheckedContinuation<Int32, Never>?

    /// Spawns `executableURL` as the leader of a brand-new process group,
    /// with `stdinPipe`/`stdoutPipe`/`stderrPipe` wired to its standard
    /// streams. The three pipes' "other" ends (the ones MacDown itself
    /// will read/write) are left untouched here — the caller closes its
    /// own now-unneeded copies of the child's ends after this returns.
    func spawn(
        executableURL: URL,
        workingDirectoryURL: URL,
        environment: [String: String],
        pipes: StandardStreamPipes
    ) throws {
        let stdinRead = pipes.stdin.fileHandleForReading.fileDescriptor
        let stdinWrite = pipes.stdin.fileHandleForWriting.fileDescriptor
        let stdoutRead = pipes.stdout.fileHandleForReading.fileDescriptor
        let stdoutWrite = pipes.stdout.fileHandleForWriting.fileDescriptor
        let stderrRead = pipes.stderr.fileHandleForReading.fileDescriptor
        let stderrWrite = pipes.stderr.fileHandleForWriting.fileDescriptor

        // `fork()` (which `posix_spawn` performs internally) duplicates
        // this **entire process's** fd table, not just the three pipes
        // this call knows about. MacDown can have more than one filter
        // running at once (finding #1's own concurrent-invocation test),
        // so without this, a *second*, concurrently-spawned child would
        // inherit *this* session's pipe fds too — file_actions below only
        // knows to close this session's own six fds, leaving the other
        // session's fds open in the wrong process and preventing its
        // stdout/stderr from ever reaching real EOF. Marking every fd
        // `FD_CLOEXEC` here means only an explicit `adddup2` below (which
        // always clears `FD_CLOEXEC` on its target) survives into any
        // child process's post-`exec` fd table — a concurrent, unrelated
        // spawn's file_actions never mention these fds, so the kernel
        // closes its inherited copies automatically at `exec`.
        for descriptor in [stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite] {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }

        // `posix_spawn_file_actions_t`/`posix_spawnattr_t` import as
        // optional opaque pointers on this SDK, not plain structs — the
        // `_init` functions allocate their backing storage into the
        // `Optional`, which is why these are declared `nil` rather than
        // default-constructed.
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_addchdir(&fileActions, workingDirectoryURL.path)
        posix_spawn_file_actions_adddup2(&fileActions, stdinRead, 0)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, 1)
        posix_spawn_file_actions_adddup2(&fileActions, stderrWrite, 2)
        // Everything else — both "other" ends the child never touches, and
        // the three source fds the dup2s above just duplicated from — must
        // be closed in the child. Left open, they would be additional
        // writable references to MacDown's own read pipes that a
        // descendant could inherit across a further fork, which is exactly
        // how finding #1's fake-EOF timer became "necessary" in the first
        // remediation: a lingering process holding a duplicate fd keeps
        // the real read end from ever seeing EOF.
        for descriptor in [stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite]
            where descriptor > 2 {
            posix_spawn_file_actions_addclose(&fileActions, descriptor)
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF))
        // `0` is POSIX shorthand for "make the new process its own group
        // leader" — the group id becomes whatever pid the kernel assigns.
        posix_spawnattr_setpgroup(&attr, 0)
        // `TextFilterProcessSession` ignores SIGPIPE process-wide so that
        // writing to a script that never reads stdin doesn't kill MacDown
        // itself. A disposition of `SIG_IGN` — unlike a custom handler —
        // survives `exec`, so without `POSIX_SPAWN_SETSIGDEF` every
        // process in the spawned tree would silently inherit "ignore
        // SIGPIPE" too. That is exactly what caused an intermediate
        // pipeline stage (e.g. `tr` in `yes | tr -d '\n' | head -c N`) to
        // never terminate when its downstream reader closed early: with
        // SIGPIPE ignored, a broken-pipe write became a recoverable EPIPE
        // return value instead of the default terminate-on-SIGPIPE
        // behavior most Unix filters rely on. Resetting SIGPIPE to its
        // default disposition for the spawned tree — exactly what
        // `Foundation.Process` already does internally — restores normal
        // pipeline semantics regardless of what MacDown's own process has
        // configured for itself.
        var resetSignals = sigset_t()
        sigemptyset(&resetSignals)
        sigaddset(&resetSignals, SIGPIPE)
        posix_spawnattr_setsigdefault(&attr, &resetSignals)

        let path = executableURL.path
        let argv0 = strdup(path)
        defer { free(argv0) }
        let envPointers: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        defer { for pointer in envPointers {
            free(pointer)
        } }

        var childPID: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [argv0, nil]
        var envp = envPointers + [nil]
        let spawnResult = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envpBuffer in
                posix_spawn(&childPID, path, &fileActions, &attr, argvBuffer.baseAddress, envpBuffer.baseAddress)
            }
        }
        guard spawnResult == 0 else { throw SpawnError.posixError(spawnResult) }

        lock.lock()
        pid = childPID
        lock.unlock()
        installExitSource(pid: childPID)
    }

    private func installExitSource(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            self?.reap(pid: pid)
        }
        source.resume()
        lock.lock()
        exitSource = source
        lock.unlock()
    }

    /// Reaps the direct child via `waitpid` the moment the kernel signals
    /// its exit, so it never lingers as a zombie that would make
    /// `groupStillExists()` report a false positive for a group whose only
    /// remaining "member" is one MacDown has simply not collected yet.
    private func reap(pid: pid_t) {
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        let code = Self.isExited(status) ? Self.exitCode(status) : Self.terminatingSignal(status)
        lock.lock()
        exitStatus = code
        let pending = exitContinuation
        exitContinuation = nil
        lock.unlock()
        pending?.resume(returning: code)
    }

    /// Suspends until the direct child has exited, returning its exit code
    /// (or, if it died from an uncaught signal, the signal number — mirrors
    /// `Foundation.Process.terminationStatus`'s dual-purpose meaning).
    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitStatus {
                lock.unlock()
                continuation.resume(returning: exitStatus)
                return
            }
            exitContinuation = continuation
            lock.unlock()
        }
    }

    /// Whether any process in this child's process group still exists.
    /// `kill(2)` with signal `0` checks existence/permission without
    /// delivering a signal; a negative pid addresses the whole process
    /// group rather than one pid. Only meaningful once `spawn` has
    /// succeeded — the group id equals the leader's own pid.
    func groupStillExists() -> Bool {
        guard let pid = currentPID else { return false }
        if kill(-pid, 0) == 0 {
            return true
        }
        // `ESRCH` ("no such process") is the only result that actually
        // confirms the group is empty. Any other failure — most notably
        // `EPERM`, observed in practice the instant this session's own
        // `reap()` consumes the group leader's zombie and its pid becomes
        // momentarily eligible for reuse/reassignment — is not evidence of
        // emptiness. Treating it as confirmed-gone would silently repeat
        // finding #1's mistake one level up: manufacturing a "contained"
        // fact this session does not actually have. Fail closed instead
        // by reporting the group as still present, so the caller keeps
        // waiting/escalating rather than declaring victory early.
        return errno != ESRCH
    }

    /// Sends `signal` to every process currently in the group. Never signals
    /// MacDown's own process group: `pid` is always the *child's* pid,
    /// established as a distinct new group by `spawn`, never `0`/our own
    /// pid, so `-pid` can never resolve to the caller's own group.
    func terminateGroup(_ signal: Int32) {
        guard let pid = currentPID else { return }
        _ = killpg(pid, signal)
    }

    private var currentPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }

    // MARK: - `wait(2)` status decoding

    /// `wait(2)`'s status word packs the low 7 bits as the terminating
    /// signal (`0` means "exited normally") and, when it exited normally,
    /// bits 8-15 as the exit code. `<sys/wait.h>`'s `WIFEXITED`/
    /// `WEXITSTATUS` macros encode exactly this, but Swift's Clang importer
    /// does not import function-like macros, so this replicates the same
    /// well-known BSD/Darwin encoding directly.
    private static func isExited(_ status: Int32) -> Bool {
        (status & 0x7F) == 0
    }

    private static func exitCode(_ status: Int32) -> Int32 {
        (status >> 8) & 0xFF
    }

    private static func terminatingSignal(_ status: Int32) -> Int32 {
        status & 0x7F
    }
}
