import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter process-group cleanup ownership")
struct FixtureProcessGroupCleanupTests {
    private final class ReapTransitionProbe: @unchecked Sendable {
        private let entered = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var signalAttempts = 0

        func pauseAfterDisarmingOwnership() {
            entered.signal()
            release.wait()
        }

        func waitForDisarm() -> Bool {
            entered.wait(timeout: .now() + .seconds(1)) == .success
        }

        func releaseReap() {
            release.signal()
        }

        func recordSignal(
            _ group: TextFilterProcessGroup,
            _ signal: Int32
        ) -> TextFilterProcessGroup.SignalOutcome {
            lock.lock()
            signalAttempts += 1
            lock.unlock()
            return group.terminateGroup(signal)
        }

        var attemptedSignalCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return signalAttempts
        }
    }

    private final class ReusedIdentityProbe: @unchecked Sendable {
        private let original: FixtureProcessIdentity
        private let replacement: FixtureProcessIdentity
        private let lock = NSLock()
        private var reapFinished = false

        init(original: FixtureProcessIdentity) {
            self.original = original
            replacement = FixtureProcessIdentity(
                pid: original.pid,
                startSeconds: original.startSeconds + 1,
                startMicroseconds: original.startMicroseconds
            )
        }

        func identity(for pid: pid_t) -> FixtureProcessIdentity? {
            lock.lock()
            defer { lock.unlock() }
            guard pid == original.pid else { return nil }
            return reapFinished ? replacement : original
        }

        func markReapFinished() {
            lock.lock()
            reapFinished = true
            lock.unlock()
        }
    }

    private final class UnconfirmedMembershipProbe: @unchecked Sendable {
        private let entered = DispatchSemaphore(value: 0)

        func reportUnconfirmed() -> TextFilterProcessGroup.MembershipState {
            entered.signal()
            return .unconfirmed
        }

        func waitForUnconfirmed() -> Bool {
            entered.wait(timeout: .now() + .seconds(1)) == .success
        }
    }

    private static func exitZeroScript(in directory: URL) throws -> URL {
        try TextFilterFixtures.makeExecutableScript("#!/bin/sh\nexit 0\n", named: "exit0.sh", in: directory)
    }

    @Test func reapDisarmsConcurrentCancellationBeforeReleasingTheLeaderIdentity() async throws {
        try await TextFilterFixtures.withTemporaryDirectory { directory in
            let group = TextFilterProcessGroup()
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )

            let probe = ReapTransitionProbe()
            let cleanup = FixtureProcessGroupCleanup(
                group: group,
                beforeReap: { probe.pauseAfterDisarmingOwnership() },
                terminate: { group, signal in probe.recordSignal(group, signal) }
            )
            _ = await group.waitForExit()
            let reapTask = Task.detached { cleanup.reapLeader() }
            defer { probe.releaseReap() }

            #expect(probe.waitForDisarm())
            #expect(cleanup.terminateIfOwned(SIGKILL) == nil)
            probe.releaseReap()
            #expect(await reapTask.value)
            #expect(cleanup.isOwnershipReleased)
            #expect(probe.attemptedSignalCount == 0)
        }
    }

    @Test func pidReuseAfterReapReleasesOwnershipWithoutAStaleSignal() async throws {
        try await TextFilterFixtures.withTemporaryDirectory { directory in
            let group = TextFilterProcessGroup()
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )
            let pid = try #require(group.pid)
            let original = try #require(TextFilterFixtures.processIdentity(pid))
            let identityProbe = ReusedIdentityProbe(original: original)
            let signalProbe = ReapTransitionProbe()
            let cleanup = FixtureProcessGroupCleanup(
                group: group,
                processIdentity: { identityProbe.identity(for: $0) },
                processIsGone: { _ in false },
                afterReap: { identityProbe.markReapFinished() },
                terminate: { group, signal in signalProbe.recordSignal(group, signal) }
            )
            _ = await group.waitForExit()

            #expect(cleanup.reapLeader())
            #expect(cleanup.isOwnershipReleased)
            #expect(cleanup.terminateIfOwned(SIGKILL) == nil)
            #expect(signalProbe.attemptedSignalCount == 0)
        }
    }

    @Test func unconfirmedMembershipCannotSignalWhileReapHasDisarmedOwnership() async throws {
        try await TextFilterFixtures.withTemporaryDirectory { directory in
            let group = TextFilterProcessGroup()
            let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
            try group.spawn(
                executableURL: Self.exitZeroScript(in: directory),
                workingDirectoryURL: directory,
                environment: [:],
                pipes: pipes
            )

            let reapProbe = ReapTransitionProbe()
            let membershipProbe = UnconfirmedMembershipProbe()
            let cleanup = FixtureProcessGroupCleanup(
                group: group,
                beforeReap: { reapProbe.pauseAfterDisarmingOwnership() },
                terminate: { group, signal in reapProbe.recordSignal(group, signal) }
            )
            let owner = TextFilterFixtures.TaskOwner()
            try await TextFilterFixtures.registerProcessGroupCleanup(
                cleanup: cleanup,
                with: owner,
                membershipState: { membershipProbe.reportUnconfirmed() }
            )
            _ = await group.waitForExit()

            let reapTask = Task.detached { cleanup.reapLeader() }
            defer { reapProbe.releaseReap() }
            #expect(reapProbe.waitForDisarm())

            let joinTask = await owner.cancelAllAndCreateJoinTask()
            #expect(membershipProbe.waitForUnconfirmed())
            #expect(reapProbe.attemptedSignalCount == 0)

            reapProbe.releaseReap()
            let report = await joinTask.value
            #expect(report.unresolved.isEmpty)
            #expect(await reapTask.value)
            #expect(cleanup.isOwnershipReleased)
            #expect(reapProbe.attemptedSignalCount == 0)
        }
    }
}
