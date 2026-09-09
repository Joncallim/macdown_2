import Darwin
import Dispatch
import Foundation

/// Low-level process-group spawn/termination/exit mechanics, isolated from
/// `TextFilterProcessSession`'s I/O and verdict orchestration so each can be
/// reasoned about independently (second through fourth adversarial passes).
///
/// `Foundation.Process` has no API to place a child into its own process
/// group **before** it execs. That containment has to be established
/// atomically as part of the spawn itself — a parent-side `setpgid` call
/// issued after `Process.run()` returns is already too late if the child
/// forks a grandchild in the window before the parent gets scheduled again.
/// This therefore spawns via `posix_spawn` with
/// `POSIX_SPAWN_SETPGROUP`/`posix_spawnattr_setpgroup(_:0)`.
///
/// Once spawned this way, the child's pid is also its process-group id, so
/// every group-lifetime operation addresses the whole initial invocation
/// group by that pinned identity.
///
/// ## PID/PGID identity and exit-observation safety
///
/// The group leader's exit is observed with `waitid(..., WNOWAIT)`, not
/// `waitpid`, so the zombie deliberately remains in the process table while
/// this session might still signal or inspect its group. A reaped pid is
/// eligible for reuse; holding the zombie prevents this invocation from ever
/// signalling an unrelated, later process group with the same numeric id.
///
/// Fourth-pass hardening adds the inverse ordering requirement: before
/// `reapLeader()` releases that pinned identity, it performs its own
/// non-blocking `waitid(..., WNOWAIT | WNOHANG)` observation and records the
/// exit status. This guarantees any `waitForExit()` continuation is resumed
/// even when process-table containment confirmation beats the asynchronous
/// DispatchSource exit callback. Reaping can no longer strand that observer
/// forever with a later `ECHILD`.
final class TextFilterProcessGroup: @unchecked Sendable {
    enum SpawnError: Error, CustomStringConvertible {
        /// A POSIX setup/spawn call returned an error.
        case posixError(Int32, step: String)
        /// A `strdup` allocation for `argv`/the environment failed.
        case allocationFailed(step: String)

        var description: String {
            switch self {
            case let .posixError(code, step):
                "\(step): \(String(cString: strerror(code)))"
            case let .allocationFailed(step):
                "\(step): allocation failed"
            }
        }
    }

    /// Bundles the three standard-stream pipes so `spawn(executableURL:
    /// workingDirectoryURL:environment:pipes:)` stays within the project's
    /// function-parameter-count budget.
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
    private var leaderReaped = false
    private var leaderReapInProgress = false
    private let installsExitSource: Bool

    /// `installsExitSource` is a deterministic test seam for the fourth-pass
    /// reap/observation race. Production always uses the default `true`.
    init(installsExitSource: Bool = true) {
        self.installsExitSource = installsExitSource
    }

    /// Spawns `executableURL` as the leader of a brand-new process group,
    /// with the three pipes wired to its standard streams. The pipes' "other"
    /// ends (the ones MacDown itself will read/write) are left untouched here;
    /// the caller closes its now-unneeded copies after this returns.
    ///
    /// Every fallible setup call is checked. A failure at any step throws
    /// before launch rather than continuing with partially configured file
    /// actions/attributes — a dropped stdout `dup2`, for example, could
    /// otherwise turn a launch-configuration defect into a successful empty
    /// replacement of the user's text.
    func spawn(
        executableURL: URL,
        workingDirectoryURL: URL,
        environment: [String: String],
        pipes: StandardStreamPipes
    ) throws {
        let stdinRead = pipes.stdin.fileHandleForReading.fileDescriptor
        let stdoutWrite = pipes.stdout.fileHandleForWriting.fileDescriptor
        let stderrWrite = pipes.stderr.fileHandleForWriting.fileDescriptor

        var fileActions: posix_spawn_file_actions_t?
        try Self.checked(posix_spawn_file_actions_init(&fileActions), step: "file_actions_init")
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try Self.checked(
            posix_spawn_file_actions_addchdir(&fileActions, workingDirectoryURL.path),
            step: "addchdir"
        )
        try Self.checked(posix_spawn_file_actions_adddup2(&fileActions, stdinRead, 0), step: "adddup2(stdin)")
        try Self.checked(posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, 1), step: "adddup2(stdout)")
        try Self.checked(posix_spawn_file_actions_adddup2(&fileActions, stderrWrite, 2), step: "adddup2(stderr)")
        // `POSIX_SPAWN_CLOEXEC_DEFAULT` closes every non-stdio descriptor in
        // the child atomically as part of spawn, avoiding the cross-session
        // inheritance window a parent-side FD_CLOEXEC loop would create.

        var attr: posix_spawnattr_t?
        try Self.checked(posix_spawnattr_init(&attr), step: "attr_init")
        defer { posix_spawnattr_destroy(&attr) }

        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT
        try Self.checked(posix_spawnattr_setflags(&attr, Int16(flags)), step: "setflags")
        // `0` means the child becomes leader of a new group named after its
        // kernel-assigned pid.
        try Self.checked(posix_spawnattr_setpgroup(&attr, 0), step: "setpgroup")

        // MacDown no longer mutates its own SIGPIPE disposition. Reset only
        // the spawned invocation to the normal default so pipeline semantics
        // remain conventional inside the filter process group.
        var resetSignals = sigset_t()
        try Self.checkedErrno(sigemptyset(&resetSignals), step: "sigemptyset")
        try Self.checkedErrno(sigaddset(&resetSignals, SIGPIPE), step: "sigaddset(SIGPIPE)")
        try Self.checked(posix_spawnattr_setsigdefault(&attr, &resetSignals), step: "setsigdefault")

        let path = executableURL.path
        guard let argv0 = strdup(path) else { throw SpawnError.allocationFailed(step: "strdup(argv0)") }
        defer { free(argv0) }

        var envPointers: [UnsafeMutablePointer<CChar>?] = []
        defer {
            for pointer in envPointers {
                free(pointer)
            }
        }
        for (key, value) in environment {
            guard let pointer = strdup("\(key)=\(value)") else {
                throw SpawnError.allocationFailed(step: "strdup(environment)")
            }
            envPointers.append(pointer)
        }

        var childPID: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [argv0, nil]
        var envp = envPointers + [nil]
        let spawnResult = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envpBuffer in
                posix_spawn(&childPID, path, &fileActions, &attr, argvBuffer.baseAddress, envpBuffer.baseAddress)
            }
        }
        try Self.checked(spawnResult, step: "posix_spawn")

        lock.lock()
        pid = childPID
        lock.unlock()
        if installsExitSource {
            installExitSource(pid: childPID)
        }
    }

    private static func checked(_ result: Int32, step: String) throws {
        guard result == 0 else { throw SpawnError.posixError(result, step: step) }
    }

    /// `sigemptyset`/`sigaddset` use the errno convention (`-1` + errno),
    /// unlike the `posix_spawn*` family which returns its error code directly.
    private static func checkedErrno(_ result: Int32, step: String) throws {
        guard result == 0 else { throw SpawnError.posixError(errno, step: step) }
    }

    private func installExitSource(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            self?.recordExitFact(pid: pid)
        }
        source.resume()
        lock.lock()
        exitSource = source
        lock.unlock()
    }

    /// Records the direct child's exit status without reaping it. `WNOHANG`
    /// makes this safe both from the DispatchSource exit callback and from
    /// `reapLeader()`'s synchronous pre-reap observation. `EINTR` is retried;
    /// any other failure remains fail-closed and is never invented as a zero
    /// exit status.
    private func recordExitFact(pid: pid_t) {
        guard let code = observedExitStatus(pid: pid) else { return }
        recordExitStatus(code)
    }

    private func observedExitStatus(pid: pid_t) -> Int32? {
        var info = siginfo_t()
        while true {
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) == 0 {
                // POSIX specifies si_pid == 0 when WNOHANG finds no child in
                // a waitable state. Never interpret that as exit status 0.
                guard info.si_pid == pid else { return nil }
                return info.si_status
            }
            guard errno == EINTR else { return nil }
        }
    }

    private func recordExitStatus(_ code: Int32) {
        lock.lock()
        if exitStatus != nil {
            lock.unlock()
            return
        }
        exitStatus = code
        let pending = exitContinuation
        exitContinuation = nil
        lock.unlock()
        pending?.resume(returning: code)
    }

    /// Suspends until the direct child has exited, returning its exit code
    /// (or, if it died from an uncaught signal, the terminating signal
    /// number — matching `Foundation.Process.terminationStatus`'s
    /// dual-purpose meaning).
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

    /// Sends `signal` to every process currently in the group. Never signals
    /// MacDown's own process group: `pid` is always the spawned child's pid,
    /// established as a distinct group before exec.
    func terminateGroup(_ signal: Int32) {
        guard let pid = currentPID else { return }
        _ = killpg(pid, signal)
    }

    /// Reaps the group leader only after the session has finished every
    /// group-lifetime operation. Before releasing the pid/pgid identity, it
    /// synchronously records an already-exited leader with `waitid(WNOWAIT |
    /// WNOHANG)`. This closes a fourth-pass race where containment could see
    /// only a zombie, return, and reap it before the asynchronous exit source
    /// had resumed `waitForExit()`; that later callback then received ECHILD
    /// and left the observer task suspended indefinitely.
    ///
    /// Still non-blocking: on a genuinely live/unconfirmed process this does
    /// not reap anything, preserving identity safety. The in-progress flag
    /// also makes simultaneous accidental callers safe: only one can ever
    /// execute `waitpid` against the pinned identity.
    func reapLeader() {
        lock.lock()
        guard let pid, !leaderReaped, !leaderReapInProgress else {
            lock.unlock()
            return
        }
        leaderReapInProgress = true
        lock.unlock()

        // If the leader is already a zombie, guarantee the exit continuation
        // observes it before waitpid can make it disappear from the table.
        recordExitFact(pid: pid)

        var status: Int32 = 0
        var reaped: pid_t = 0
        while true {
            reaped = waitpid(pid, &status, WNOHANG)
            if reaped != -1 || errno != EINTR {
                break
            }
        }

        lock.lock()
        if reaped == pid {
            leaderReaped = true
        }
        leaderReapInProgress = false
        lock.unlock()
    }

    private var currentPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }
}
