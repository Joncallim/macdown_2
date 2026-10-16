import Darwin
import Foundation
import Testing
@testable import TextFilters

/// Direct, sub-`TextFilterRunner` coverage of `TextFilterProcessGroup`
/// itself: checked spawn setup, identity-pinned exit observation/reaping,
/// and verified process-group membership.
@Suite("TextFilterProcessGroup")
struct TextFilterProcessGroupTests {
    private enum FixtureFailure: Error {
        case readiness
    }

    /// A leader that exits promptly with status 0. `spawn()` never passes
    /// arguments (structured launch only — always a real script file, not
    /// a bare interpreter, which would otherwise block reading stdin as a
    /// script itself).
    private static func exitZeroScript(in directory: URL) throws -> URL {
        try TextFilterFixtures.makeExecutableScript("#!/bin/sh\nexit 0\n", named: "exit0.sh", in: directory)
    }

    private static func withOwnedGroup<T: Sendable>(
        startsExitObserverAutomatically: Bool = true,
        _ operation: (URL, TextFilterProcessGroup, FixtureProcessGroupCleanup) async throws -> T
    ) async throws -> T {
        try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
            let group = TextFilterProcessGroup(startsExitObserverAutomatically: startsExitObserverAutomatically)
            let cleanup = try await TextFilterFixtures.registerProcessGroupCleanup(group, with: owner)
            return try await operation(directory, group, cleanup)
        }
    }

    /// A pipe whose read end names a descriptor number at or above
    /// `RLIMIT_NOFILE`, which the process can never allocate. Closing a real
    /// pipe's descriptor instead hands its number back to the table, where a
    /// concurrently running test can be given it (making this test pass or
    /// fail by timing) and the `Pipe`'s own later close then hits that
    /// other test's descriptor.
    private final class UnopenableReadEndPipe: Pipe, @unchecked Sendable {
        private let unopenable = FileHandle(
            fileDescriptor: UnopenableReadEndPipe.neverAllocatedDescriptor(),
            closeOnDealloc: false
        )

        override var fileHandleForReading: FileHandle {
            unopenable
        }

        private static func neverAllocatedDescriptor() -> Int32 {
            var limit = rlimit()
            getrlimit(RLIMIT_NOFILE, &limit)
            return Int32(clamping: min(limit.rlim_cur, UInt64(Int32.max - 1)))
        }
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
        let pipes = TextFilterProcessGroup.StandardStreamPipes(
            stdin: UnopenableReadEndPipe(),
            stdout: Pipe(),
            stderr: Pipe()
        )

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
        try await Self.withOwnedGroup { directory, group, cleanup in
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

            cleanup.reapLeader()

            #expect(cleanup.isOwnershipReleased)
            #expect(kill(pid, 0) == -1 && errno == ESRCH, "reapLeader() must actually release the pid")
        }
    }

    /// Fifth-pass race regression: the direct child is allowed to become a
    /// zombie *before* exit observation begins. Darwin's EVFILT_PROC attach
    /// path cannot safely guarantee that late registration sees this state;
    /// a direct `waitid(WNOWAIT)` on our child must still return status 0.
    @Test func exitObservationStartedAfterTheLeaderAlreadyExitedStillReportsItsStatus() async throws {
        try await Self.withOwnedGroup(startsExitObserverAutomatically: false) { directory, group, cleanup in
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )

            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while group.verifiedMembershipState() == .live, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(group.verifiedMembershipState() == .empty, "the leader must already be a held zombie")

            group.startExitObservation()

            #expect(await group.waitForExit() == 0, "late observation must not miss an already-exited child")
            cleanup.reapLeader()
        }
    }

    /// Fourth-pass race regression: process-table containment can observe the
    /// zombie leader before the worker-queue observer resumes. A reap at that
    /// point used to be capable of removing the leader before the observer had
    /// preserved the exit fact. Disable automatic observation deterministically:
    /// `reapLeader()` itself must record the exit before removing the zombie,
    /// so a subsequent waiter returns immediately.
    @Test func reapRecordsAnExitedLeaderBeforeRemovingItEvenWithoutTheAsyncObserver() async throws {
        try await Self.withOwnedGroup(startsExitObserverAutomatically: false) { directory, group, cleanup in
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

            cleanup.reapLeader()

            #expect(kill(pid, 0) == -1 && errno == ESRCH)
            #expect(await group.waitForExit() == 0, "pre-reap observation must preserve the exit fact for late waiters")
        }
    }

    // MARK: - Verified group membership

    @Test func verifiedMembershipIgnoresAHeldZombieLeaderWithNoLiveDescendant() async throws {
        try await Self.withOwnedGroup { directory, group, cleanup in
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )
            _ = await group.waitForExit()

            #expect(group.verifiedMembershipState() == .empty)

            cleanup.reapLeader()
        }
    }

    @Test func verifiedMembershipDetectsALiveDescendantAlongsideAHeldZombieLeader() async throws {
        try await Self.withOwnedGroup { directory, group, cleanup in
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            let scriptURL = try TextFilterFixtures.makeExecutableScript(
                "#!/bin/sh\nsleep 30 &\nexit 0\n", named: "bg.sh", in: directory
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

            cleanup.reapLeader()
        }
    }

    /// Darwin answers `EPERM`, **not** `ESRCH`, when the only member of a
    /// process group is this invocation's own deliberately-unreaped zombie
    /// leader — a group that is in fact fully contained. Containment must
    /// therefore never read a failed `killpg` as "live members remain":
    /// doing so turned every filter whose child had already exited by
    /// containment time into a spurious `.terminationUnconfirmed`, which
    /// is timing-dependent and so surfaced only on CI. The process-table
    /// snapshot is the authority; this pins both halves of that.
    @Test func killpgOnAZombieOnlyGroupFailsWithEPERMWhileMembershipReadsEmpty() async throws {
        try await Self.withOwnedGroup { directory, group, cleanup in
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )
            _ = await group.waitForExit()

            #expect(group.verifiedMembershipState() == .empty, "a held zombie leader alone is a contained group")
            #expect(
                group.terminateGroup(SIGTERM) == .failed(EPERM),
                "Darwin reports EPERM for a zombie-only group — this must not be read as a containment failure"
            )

            cleanup.reapLeader()
        }
    }

    @Test func reapLeaderIsIdempotentAndSafeToCallMoreThanOnce() async throws {
        try await Self.withOwnedGroup { directory, group, cleanup in
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )
            _ = await group.waitForExit()

            #expect(cleanup.reapLeader())
            group.reapLeader() // production reaping must remain idempotent after ownership release
        }
    }

    @Test func ownedProcessGroupIsTerminatedWhenReadinessFailsBeforeObservation() async throws {
        var spawnedPID: pid_t?

        do {
            try await Self.withOwnedGroup { directory, group, _ in
                let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
                let script = try TextFilterFixtures.makeExecutableScript(
                    "#!/bin/sh\nsleep 30\n", named: "readiness.sh", in: directory
                )
                try group.spawn(
                    executableURL: script,
                    workingDirectoryURL: directory,
                    environment: [:],
                    pipes: pipes
                )
                spawnedPID = group.pid
                throw FixtureFailure.readiness
            }
            Issue.record("expected readiness failure")
        } catch FixtureFailure.readiness {
            // The scope owner must terminate and reap the exact group before
            // this primary readiness failure is rethrown.
        }

        let pid = try #require(spawnedPID)
        #expect(TextFilterFixtures.processIsGone(pid), "readiness failure must not leak the owned leader")
    }
}
