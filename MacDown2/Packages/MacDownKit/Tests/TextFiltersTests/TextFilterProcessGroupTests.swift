import Darwin
import Foundation
import Testing
@testable import TextFilters

/// Direct, sub-`TextFilterRunner` coverage of `TextFilterProcessGroup`
/// itself: checked spawn setup, identity-pinned exit observation/reaping,
/// and verified process-group membership.
@Suite("TextFilterProcessGroup")
struct TextFilterProcessGroupTests {
    /// A leader that exits promptly with status 0. `spawn()` never passes
    /// arguments (structured launch only — always a real script file, not
    /// a bare interpreter, which would otherwise block reading stdin as a
    /// script itself).
    private static func exitZeroScript(in directory: URL) throws -> URL {
        try TextFilterFixtures.makeExecutableScript("#!/bin/sh\nexit 0\n", named: "exit0.sh", in: directory)
    }

    // MARK: - Checked setup/spawn failures

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
    /// longer exists by the time `spawn()` launches. Whether this is caught
    /// by `adddup2` or only by `posix_spawn` is a libc implementation detail;
    /// the invariant is that the launch cannot continue with an unintended
    /// inherited stdin.
    @Test func aClosedSourceDescriptorFailsTheSpawnRatherThanSilentlyLaunching() {
        let group = TextFilterProcessGroup()
        let stdinPipe = Pipe()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: stdinPipe, stdout: Pipe(), stderr: Pipe())
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

    // MARK: - Leader identity stays pinned until reapLeader()

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
        #expect(kill(pid, 0) == 0, "the leader must remain a held zombie until explicit reap")

        group.reapLeader()

        #expect(kill(pid, 0) == -1 && errno == ESRCH, "reapLeader() must actually release the pid")
    }

    /// Fourth-pass race regression: process-table containment can observe the
    /// zombie leader before the asynchronous DispatchSource callback runs. A
    /// reap at that point used to make the callback's later waitid return
    /// ECHILD, leaving `waitForExit()` suspended forever. Disable the exit
    /// source deterministically: `reapLeader()` itself must record the exit
    /// before removing the zombie, so a subsequent waiter returns immediately.
    @Test func reapRecordsAnExitedLeaderBeforeRemovingItEvenWithoutTheAsyncExitSource() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = TextFilterProcessGroup(installsExitSource: false)
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        try group.spawn(
            executableURL: Self.exitZeroScript(in: directory),
            workingDirectoryURL: directory,
            environment: [:],
            pipes: pipes
        )
        let pid = try #require(group.pid)

        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while group.verifiedMembershipState() == .live, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(group.verifiedMembershipState() == .empty, "the leader must have reached its held-zombie state")

        group.reapLeader()

        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(await group.waitForExit() == 0, "pre-reap observation must preserve the exit fact for late waiters")
    }

    // MARK: - Verified group membership

    @Test func verifiedMembershipIgnoresAHeldZombieLeaderWithNoLiveDescendant() async throws {
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

        #expect(group.verifiedMembershipState() == .empty)

        group.reapLeader()
    }

    @Test func verifiedMembershipDetectsALiveDescendantAlongsideAHeldZombieLeader() async throws {
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
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

        #expect(group.verifiedMembershipState() == .live, "the backgrounded sleep must still be live")

        group.terminateGroup(SIGKILL)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while group.verifiedMembershipState() != .empty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(group.verifiedMembershipState() == .empty, "SIGKILL must reach the live descendant")

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
