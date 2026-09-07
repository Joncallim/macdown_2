import Darwin
import Foundation
import Testing
@testable import TextFilters

/// Direct, sub-`TextFilterRunner` coverage of `TextFilterProcessGroup`
/// itself (third-adversarial-pass findings #2/#3): checked spawn setup,
/// and the leader-not-reaped-until-`reapLeader()` identity-safety
/// ordering that `groupHasLiveMembers()`/`terminateGroup(_:)` depend on.
@Suite("TextFilterProcessGroup")
struct TextFilterProcessGroupTests {
    /// A leader that exits promptly with status 0. `spawn()` never passes
    /// arguments (structured launch only — always a real script file, not
    /// a bare interpreter, which would otherwise block reading stdin as a
    /// script itself).
    private static func exitZeroScript(in directory: URL) throws -> URL {
        try TextFilterFixtures.makeExecutableScript("#!/bin/sh\nexit 0\n", named: "exit0.sh", in: directory)
    }

    // MARK: - Finding #3: every setup/spawn failure is checked, never best-effort

    @Test func aNonexistentWorkingDirectoryFailsTheSpawnRatherThanSilentlyLaunching() {
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        let missingDirectory = URL(fileURLWithPath: "/does/not/exist/\(UUID().uuidString)")

        #expect(throws: TextFilterProcessGroup.SpawnError.self) {
            try group.spawn(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                workingDirectoryURL: missingDirectory,
                environment: [:],
                pipes: pipes
            )
        }
    }

    /// A source descriptor `adddup2` was told to duplicate onto stdin no
    /// longer exists by the time `spawn()` actually launches. Whether
    /// this is caught by `adddup2` itself or only surfaces via
    /// `posix_spawn`'s own return code is a libc implementation detail;
    /// what this test actually guards is that `spawn()` checks *some*
    /// call in the chain rather than continuing to launch with fd 0 left
    /// as whatever it already was — a dropped stdin dup2 could run the
    /// command connected to something other than the pipe MacDown wired
    /// up for it.
    @Test func aClosedSourceDescriptorFailsTheSpawnRatherThanSilentlyLaunching() {
        let group = TextFilterProcessGroup()
        let stdinPipe = Pipe()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: stdinPipe, stdout: Pipe(), stderr: Pipe())
        // Closed last, immediately before `spawn()`: closing it any
        // earlier risks the freed fd number being silently reassigned to
        // one of the *other* pipes created afterward, which would leave
        // nothing actually invalid by the time `spawn()` runs.
        close(stdinPipe.fileHandleForReading.fileDescriptor)

        #expect(throws: TextFilterProcessGroup.SpawnError.self) {
            try group.spawn(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                workingDirectoryURL: FileManager.default.temporaryDirectory,
                environment: [:],
                pipes: pipes
            )
        }
    }

    // MARK: - Finding #2: leader identity stays pinned until reapLeader()

    /// Deterministic ordering: the direct child's exit is observable
    /// (`waitForExit()` resolves) before the leader is reaped, and the
    /// leader only stops being addressable as a distinct process-table
    /// entry once `reapLeader()` is explicitly called — never as a side
    /// effect of merely observing its exit.
    @Test func leaderExitIsObservedWithoutReapingUntilReapLeaderIsCalled() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        try group.spawn(
            executableURL: Self.exitZeroScript(in: directory),
            workingDirectoryURL: directory,
            environment: [:],
            pipes: pipes
        )
        let pid = try #require(group.pid)

        let status = await group.waitForExit()
        #expect(status == 0)

        // The leader has exited (waitForExit resolved) but must still be
        // a real, un-reaped zombie -- kill(pid, 0) succeeds for a zombie
        // (it still occupies a process-table slot) and only starts
        // failing with ESRCH once the entry is actually released.
        #expect(kill(pid, 0) == 0, "the leader must still be a held zombie before reapLeader() is called")

        group.reapLeader()

        #expect(kill(pid, 0) == -1 && errno == ESRCH, "reapLeader() must actually release the pid")
    }

    /// `groupHasLiveMembers()` must not be fooled by the leader's own
    /// held zombie into reporting the group as non-empty forever: with no
    /// live descendant, it should read `false` even while this session
    /// is still deliberately holding the leader un-reaped.
    @Test func groupHasLiveMembersIgnoresAHeldZombieLeaderWithNoLiveDescendant() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        try group.spawn(
            executableURL: Self.exitZeroScript(in: directory),
            workingDirectoryURL: directory,
            environment: [:],
            pipes: pipes
        )
        _ = await group.waitForExit()

        #expect(!group.groupHasLiveMembers())

        group.reapLeader()
    }

    /// The inverse: a live descendant in the group is correctly reported
    /// even though the (unrelated) leader is simultaneously a held
    /// zombie — this is the exact distinction `kill(-pgid, 0)` cannot
    /// make once the leader is held.
    @Test func groupHasLiveMembersDetectsALiveDescendantAlongsideAHeldZombieLeader() async throws {
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        // The leader script backgrounds a long-lived descendant and exits
        // immediately, leaving the descendant as the group's only live
        // member.
        let script = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: script) }
        let scriptURL = try TextFilterFixtures.makeExecutableScript(
            "#!/bin/sh\nsleep 30 &\nexit 0\n", named: "bg.sh", in: script
        )
        try group.spawn(
            executableURL: scriptURL,
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            environment: [:],
            pipes: pipes
        )
        _ = await group.waitForExit()

        #expect(group.groupHasLiveMembers(), "the backgrounded sleep must still be reported as a live member")

        group.terminateGroup(SIGKILL)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while group.groupHasLiveMembers(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!group.groupHasLiveMembers(), "SIGKILL to the group must reach the live descendant too")

        group.reapLeader()
    }

    @Test func reapLeaderIsIdempotentAndSafeToCallMoreThanOnce() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        try group.spawn(
            executableURL: Self.exitZeroScript(in: directory),
            workingDirectoryURL: directory,
            environment: [:],
            pipes: pipes
        )
        _ = await group.waitForExit()

        group.reapLeader()
        group.reapLeader() // must not double-reap an unrelated, possibly-reused pid
    }
}
