import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter held-group cleanup")
struct FixtureHeldGroupCleanupTests {
    private enum FixtureFailure: Error {
        case heldGroupDidNotBecomeEmpty
    }

    private struct HeldGroup {
        let group: TextFilterProcessGroup
        let pipes: TextFilterProcessGroup.StandardStreamPipes
        let ready: URL
        let release: URL
    }

    private final class SignalProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0

        func record(
            _ group: TextFilterProcessGroup,
            _ signal: Int32
        ) -> TextFilterProcessGroup.SignalOutcome {
            lock.lock()
            attempts += 1
            lock.unlock()
            return group.terminateGroup(signal)
        }

        var attemptedSignalCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return attempts
        }
    }

    private final class CleanupState: @unchecked Sendable {
        private let lock = NSLock()
        private var reaped = false

        func markReaped() {
            lock.lock()
            reaped = true
            lock.unlock()
        }

        var isReaped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return reaped
        }
    }

    private actor ScopeProbe {
        private(set) var directory: URL?
        private(set) var pid: pid_t?
        private(set) var ready = false
        private(set) var finished = false

        func recordStarted(directory: URL, pid: pid_t) {
            self.directory = directory
            self.pid = pid
            ready = true
        }

        func recordFinished() {
            finished = true
        }
    }

    private static func makeHeldGroup(
        in directory: URL
    ) throws -> HeldGroup {
        let group = TextFilterProcessGroup()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
        let ready = directory.appendingPathComponent("ready")
        let release = directory.appendingPathComponent("release")
        let script = try TextFilterFixtures.makeExecutableScript(
            "#!/bin/sh\ntouch '\(ready.path)'\nwhile [ ! -f '\(release.path)' ]; do sleep 0.01; done\n",
            named: "held.sh",
            in: directory
        )
        try group.spawn(
            executableURL: script,
            workingDirectoryURL: directory,
            environment: [:],
            pipes: pipes
        )
        return HeldGroup(group: group, pipes: pipes, ready: ready, release: release)
    }

    private static func waitForReady(_ ready: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !FileManager.default.fileExists(atPath: ready.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func waitForEmpty(_ group: TextFilterProcessGroup) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while group.verifiedMembershipState() != .empty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return group.verifiedMembershipState() == .empty
    }

    private static func registerReleaseCleanup(
        release: URL,
        group: TextFilterProcessGroup,
        state: CleanupState,
        owner: TextFilterFixtures.TaskOwner
    ) async throws {
        try await owner.registerCleanup(
            cancel: {
                try? "release".write(to: release, atomically: true, encoding: .utf8)
            },
            join: {
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    if state.isReaped {
                        return .completed(nil)
                    }
                    if group.verifiedMembershipState() == .empty {
                        group.reapLeader()
                        state.markReaped()
                        return .completed(nil)
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return .unresolved("held group did not prove exit after release")
            }
        )
    }

    @Test func failedReapBecomesUnresolvedWithoutAStaleNumericSignal() async throws {
        try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
            let heldGroup = try Self.makeHeldGroup(in: directory)
            let group = heldGroup.group
            let ready = heldGroup.ready
            let release = heldGroup.release
            let state = CleanupState()
            try await Self.registerReleaseCleanup(release: release, group: group, state: state, owner: owner)
            try await Self.waitForReady(ready)
            #expect(FileManager.default.fileExists(atPath: ready.path))

            let probe = SignalProbe()
            let cleanup = FixtureProcessGroupCleanup(
                group: group,
                terminate: { group, signal in probe.record(group, signal) }
            )
            #expect(!cleanup.reapLeader())
            #expect(cleanup.unresolvedReason != nil)
            #expect(cleanup.terminateIfOwned(SIGKILL) == nil)
            #expect(probe.attemptedSignalCount == 0)

            try "release".write(to: release, atomically: true, encoding: .utf8)
            guard try await Self.waitForEmpty(group) else {
                throw FixtureFailure.heldGroupDidNotBecomeEmpty
            }
            group.reapLeader()
            state.markReaped()
            let pid = try #require(group.pid)
            #expect(TextFilterFixtures.processIsGone(pid))
        }
    }

    private static func runCancellationScenario(probe: ScopeProbe) async {
        do {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                let heldGroup = try Self.makeHeldGroup(in: directory)
                let group = heldGroup.group
                let ready = heldGroup.ready
                let release = heldGroup.release
                let pid = try #require(group.pid)
                let state = CleanupState()
                try await Self.registerReleaseCleanup(
                    release: release,
                    group: group,
                    state: state,
                    owner: owner
                )
                try await Self.waitForReady(ready)
                #expect(FileManager.default.fileExists(atPath: ready.path))
                let cleanup = FixtureProcessGroupCleanup(group: group)
                #expect(!cleanup.reapLeader())
                await probe.recordStarted(directory: directory, pid: pid)
                try await Task.sleep(for: .seconds(30))
            }
        } catch {
            await probe.recordFinished()
        }
    }

    @Test func cancellationBeforeReleaseMarkerStillJoinsTheHeldGroup() async throws {
        let probe = ScopeProbe()
        let scope = Task { await Self.runCancellationScenario(probe: probe) }
        let ready: Bool
        do {
            ready = try await withTaskCancellationHandler(operation: {
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                while await !probe.ready, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                return await probe.ready
            }, onCancel: {
                scope.cancel()
            })
        } catch {
            scope.cancel()
            _ = await scope.value
            throw error
        }
        scope.cancel()
        _ = await scope.value

        #expect(ready)
        #expect(await probe.finished)
        let directory = try #require(await probe.directory)
        let pid = try #require(await probe.pid)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(TextFilterFixtures.processIsGone(pid))
    }
}
