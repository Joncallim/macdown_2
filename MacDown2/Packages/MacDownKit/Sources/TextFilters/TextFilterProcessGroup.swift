import Darwin
import Dispatch
import Foundation

/// Low-level process-group spawn/termination/existence mechanics, isolated
/// from `TextFilterProcessSession`'s I/O and verdict orchestration so each
/// can be reasoned about independently (second-adversarial-pass finding
/// #2, redesigned again for third-adversarial-pass findings #2/#3/#4/#8).
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
///
/// ## PID/PGID identity safety (third-adversarial-pass finding #2)
///
/// The direct child (the group leader)'s exit is observed via
/// `waitid(..., WNOWAIT)`, **not** `waitpid`: the leader is deliberately
/// left as an un-reaped zombie for as long as this session might still
/// need to address the group by its pid/pgid number. A reaped pid is
/// eligible for immediate reuse by the kernel; if this type reaped the
/// leader and then later called `killpg(oldPID, ...)` after that number
/// had been reassigned to an unrelated process group, it would signal the
/// wrong processes. Holding the zombie pins the identity. `reapLeader()`
/// must be called exactly once, only after every group-lifetime operation
/// (containment, membership checks) this invocation will ever perform is
/// complete.
///
/// One consequence: `kill(-pgid, 0)`, the obvious "does this group still
/// have anyone in it" check, is unusable once the zombie leader is held —
/// it reports the group as existing purely because of that zombie,
/// indefinitely. `groupHasLiveMembers()` instead enumerates real group
/// membership via `sysctl(KERN_PROC_PGRP)` and looks at each member's
/// actual process state.
final class TextFilterProcessGroup: @unchecked Sendable {
    enum SpawnError: Error, CustomStringConvertible {
        /// A POSIX setup/spawn call returned a non-zero error code
        /// (third-adversarial-pass finding #3: every fallible call in
        /// `spawn()` is checked, none are best-effort).
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
    private var leaderReaped = false

    /// Spawns `executableURL` as the leader of a brand-new process group,
    /// with the three pipes wired to its standard streams. The pipes'
    /// "other" ends (the ones MacDown itself will read/write) are left
    /// untouched here — the caller closes its own now-unneeded copies of
    /// the child's ends after this returns.
    ///
    /// Every fallible setup call is checked (finding #3): a failure at any
    /// step throws before `posix_spawn` itself runs, rather than
    /// continuing with a partially-configured file-actions/attributes
    /// object. A silently-dropped `adddup2` for stdout, for instance,
    /// could let a command run with the app's own inherited stdout instead
    /// of MacDown's capture pipe — which would then read empty and,
    /// per this feature's own zero-exit/empty-stdout-is-success contract,
    /// turn a launch-configuration failure into "successful" deletion of
    /// the user's text.
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
        // No explicit `addclose` for every other descriptor, and no
        // parent-side `fcntl(FD_CLOEXEC)` loop, either: `POSIX_SPAWN_
        // CLOEXEC_DEFAULT` below closes everything not named by a dup2
        // action above, atomically, as part of the spawn itself
        // (third-adversarial-pass finding #4). A `fcntl` loop run after
        // `Pipe` has already created its descriptors leaves a real window,
        // between one session's pipe creation and its own `fcntl` call,
        // during which a *concurrently spawning* session's `fork()` can
        // still inherit them; this policy has no such window because
        // nothing is CLOEXEC-eligible until the kernel says so as part of
        // the same spawn.

        var attr: posix_spawnattr_t?
        try Self.checked(posix_spawnattr_init(&attr), step: "attr_init")
        defer { posix_spawnattr_destroy(&attr) }

        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT
        try Self.checked(posix_spawnattr_setflags(&attr, Int16(flags)), step: "setflags")
        // `0` is POSIX shorthand for "make the new process its own group
        // leader" — the group id becomes whatever pid the kernel assigns.
        try Self.checked(posix_spawnattr_setpgroup(&attr, 0), step: "setpgroup")
        // `TextFilterProcessSession` no longer mutates the app-wide SIGPIPE
        // disposition (third-adversarial-pass finding #8); this attribute
        // alone is what keeps the spawned tree's own SIGPIPE handling at
        // its normal default regardless of MacDown's own process state —
        // matching what `Foundation.Process` already does internally, and
        // restoring normal pipeline semantics (e.g. `tr` in
        // `yes | tr -d '\n' | head -c N` terminating on a closed
        // downstream reader) even though nothing in MacDown's own process
        // ignores SIGPIPE anymore.
        var resetSignals = sigset_t()
        sigemptyset(&resetSignals)
        sigaddset(&resetSignals, SIGPIPE)
        try Self.checked(posix_spawnattr_setsigdefault(&attr, &resetSignals), step: "setsigdefault")

        let path = executableURL.path
        guard let argv0 = strdup(path) else { throw SpawnError.allocationFailed(step: "strdup(argv0)") }
        defer { free(argv0) }

        var envPointers: [UnsafeMutablePointer<CChar>?] = []
        defer { for pointer in envPointers {
            free(pointer)
        } }
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
        installExitSource(pid: childPID)
    }

    private static func checked(_ result: Int32, step: String) throws {
        guard result == 0 else { throw SpawnError.posixError(result, step: step) }
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

    /// Records the direct child's exit status **without reaping it** —
    /// `waitid(P_PID, pid, ..., WEXITED | WNOWAIT)` reports the same
    /// `siginfo_t` exit/signal information `wait(2)` would, but leaves the
    /// zombie present in the process table so `pid` (which is also this
    /// invocation's process-group id) cannot be reassigned to an unrelated
    /// process until `reapLeader()` explicitly releases it
    /// (third-adversarial-pass finding #2).
    private func recordExitFact(pid: pid_t) {
        var info = siginfo_t()
        guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == 0 else { return }
        // `si_status` already holds the right magnitude for either case —
        // the exit code when `si_code == CLD_EXITED`, the terminating
        // signal number otherwise — with no packed encoding to unpack,
        // unlike a raw `wait(2)` status word. Collapsing both into one
        // `Int32` without a case discriminator matches `Foundation.
        // Process.terminationStatus`'s own dual-purpose meaning: callers
        // only ever check `status == 0` for success and otherwise report
        // whatever non-zero value they got.
        let code = info.si_status
        lock.lock()
        exitStatus = code
        let pending = exitContinuation
        exitContinuation = nil
        lock.unlock()
        pending?.resume(returning: code)
    }

    /// Suspends until the direct child has exited, returning its exit code
    /// (or, if it died from an uncaught signal, the terminating signal
    /// number — the two cases are not distinguished, matching
    /// `Foundation.Process.terminationStatus`'s own dual-purpose meaning).
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

    /// `true` if the process group has any member that is not a zombie.
    /// Deliberately does **not** use `kill(-pgid, 0)`: once
    /// `recordExitFact` starts holding the leader as an un-reaped zombie,
    /// `kill(-pgid, 0)` reports the group as "existing" purely because of
    /// that zombie, for as long as this session holds it — every
    /// emptiness check built on it would be vacuously true regardless of
    /// whether any real descendant is still alive (third-adversarial-pass
    /// finding #2). This enumerates real membership via
    /// `sysctl(KERN_PROC_PGRP)` and inspects each member's actual state.
    func groupHasLiveMembers() -> Bool {
        guard let pid = currentPID else { return false }
        return Self.processGroupMembers(pid).contains { $0.stat != SZOMB }
    }

    /// Sends `signal` to every process currently in the group. Never
    /// signals MacDown's own process group: `pid` is always the *child's*
    /// pid, established as a distinct new group by `spawn`, never `0`/our
    /// own pid, so `-pid` can never resolve to the caller's own group.
    /// Safe to call while the leader is a held zombie — its pid/pgid
    /// number is pinned (not eligible for reuse) for as long as this
    /// session has not yet reaped it.
    func terminateGroup(_ signal: Int32) {
        guard let pid = currentPID else { return }
        _ = killpg(pid, signal)
    }

    /// Reaps the group leader. Call exactly once, only after every
    /// group-lifetime operation this invocation will ever perform
    /// (`groupHasLiveMembers()`/`terminateGroup(_:)`) is complete — this
    /// is the point at which the pid/pgid number stops being pinned to
    /// this invocation and becomes eligible for kernel reuse
    /// (third-adversarial-pass finding #2). Idempotent; a no-op if `spawn`
    /// never succeeded or this was already called.
    ///
    /// Non-blocking (`WNOHANG`): every caller already confirmed
    /// `groupHasLiveMembers() == false`, kernel-level truth that the
    /// leader is already a zombie, so reaping should never need to wait —
    /// deliberately not gated on this instance's own `exitStatus` already
    /// being recorded by its own async exit-detection handler, which is
    /// independent of and can race behind that kernel-level fact. In the
    /// rare case containment could not actually be confirmed (this
    /// session already reported `.terminationUnconfirmed` for that), this
    /// is a safe no-op rather than a hang: leaving an unreaped zombie
    /// behind is a bounded resource leak, not a signal-identity hazard —
    /// its pid/pgid stays pinned to this invocation for exactly the same
    /// reason not reaping is the safety property finding #2 wants.
    func reapLeader() {
        lock.lock()
        guard let pid, !leaderReaped else {
            lock.unlock()
            return
        }
        lock.unlock()
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return }
        lock.lock()
        leaderReaped = true
        lock.unlock()
    }

    private var currentPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }

    // MARK: - Process-group membership enumeration

    /// Lists every process currently in group `pgid` via
    /// `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PGRP, pgid)`, each with its
    /// `p_stat` (`SZOMB` for a zombie). The group can gain members between
    /// the size query and the data query, so this retries a bounded
    /// number of times with slack padding rather than trusting one
    /// snapshot's exact size.
    private static func processGroupMembers(_ pgid: pid_t) -> [(pid: pid_t, stat: Int8)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, pgid]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0 ..< 4 {
            var querySize = 0
            guard sysctl(&mib, u_int(mib.count), nil, &querySize, nil, 0) == 0, querySize > 0 else {
                return []
            }
            let capacity = querySize / stride + 8
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var bufferSize = capacity * stride
            let result = buffer.withUnsafeMutableBytes { raw in
                sysctl(&mib, u_int(mib.count), raw.baseAddress, &bufferSize, nil, 0)
            }
            guard result == 0 else {
                if errno == ENOMEM {
                    continue
                }
                return []
            }
            let count = bufferSize / stride
            return (0 ..< count).map { (buffer[$0].kp_proc.p_pid, buffer[$0].kp_proc.p_stat) }
        }
        return []
    }
}
