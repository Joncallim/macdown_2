import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture cancellation isolation")
struct TextFilterCancellationIsolationTests {
    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private let release = DispatchSemaphore(value: 0)
        private var events: [String] = []
        private var expired = false

        var snapshot: (events: [String], expired: Bool) {
            lock.withLock { (events, expired) }
        }

        func record(_ event: String) {
            lock.withLock { events.append(event) }
        }

        func holdCancellation() {
            record("first cancellation started")
            // A deadlock guard, not the cleanup deadline under test.
            let result = release.wait(timeout: .now() + .seconds(2))
            lock.withLock {
                expired = result == .timedOut
                events.append("first cancellation finished")
            }
        }

        func releaseCancellation() {
            release.signal()
        }

        func waitUntilEntered() async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !snapshot.events.contains("first cancellation started"), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return snapshot.events.contains("first cancellation started")
        }
    }

    @Test func blockedCancellationKeepsOwnerResponsiveAndSharesTheCompleteCleanupTask() async throws {
        let probe = CancellationProbe()
        let owner = TextFilterFixtures.TaskOwner()
        defer { probe.releaseCancellation() }
        try await owner.registerCleanup(
            cancel: { probe.holdCancellation() },
            join: {
                probe.record("first join")
                return .completed(nil)
            }
        )
        try await owner.registerCleanup(
            cancel: { probe.record("second cancellation") },
            join: {
                probe.record("second join")
                return .completed(nil)
            }
        )

        let first = await owner.cancelAllAndCreateJoinTask()
        #expect(await probe.waitUntilEntered())
        let second = await owner.cancelAllAndCreateJoinTask()
        #expect(first == second)
        await #expect(throws: TextFilterFixtures.TaskOwnerError.closed) {
            try await owner.registerCleanup(cancel: {}, join: { .completed(nil) })
        }
        // Both callers obtain the same pending cleanup while cancellation is
        // held, and registration closes without waiting for that callback.
        #expect(!probe.snapshot.expired)
        #expect(probe.snapshot.events == ["first cancellation started"])

        probe.releaseCancellation()
        let firstReport = await first.value
        let secondReport = await second.value
        #expect(firstReport.failures.isEmpty && firstReport.unresolved.isEmpty)
        #expect(secondReport.failures.isEmpty && secondReport.unresolved.isEmpty)
        let events = probe.snapshot.events
        #expect(Array(events.prefix(3)) == [
            "first cancellation started", "first cancellation finished", "second cancellation",
        ])
        #expect(events.count == 5)
        #expect(Set(events.suffix(2)) == ["first join", "second join"])
        #expect(!probe.snapshot.expired)
    }

    @Test func timeoutDuringCancellationReachesTheEventualJoinBeforeDirectoryRemoval() async throws {
        let probe = CancellationProbe()
        var observedOwner: TextFilterFixtures.TaskOwner?
        var observedDirectory: URL?
        defer { probe.releaseCancellation() }
        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(cleanupTimeout: .milliseconds(25)) { directory, owner in
                    observedOwner = owner
                    observedDirectory = directory
                    try await owner.registerCleanup(
                        cancel: { probe.holdCancellation() },
                        join: {
                            probe.record(Task.isCancelled ? "join cancelled" : "join live")
                            return .completed(nil)
                        }
                    )
                }
            Issue.record("expected the watchdog to return while cancellation is held")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            if case let .cleanupTimedOut(primary, timeout) = error {
                #expect(primary == nil)
                #expect(timeout == .milliseconds(25))
            } else {
                Issue.record("unexpected fixture cleanup error: \(error)")
            }
        }

        #expect(await probe.waitUntilEntered())
        #expect(!probe.snapshot.expired)
        #expect(probe.snapshot.events == ["first cancellation started"])
        probe.releaseCancellation()
        if let owner = observedOwner, let directory = observedDirectory {
            #expect(FileManager.default.fileExists(atPath: directory.path))
            let aggregate = await owner.cancelAllAndCreateJoinTask()
            _ = await aggregate.value
            #expect(probe.snapshot.events == [
                "first cancellation started", "first cancellation finished", "join cancelled",
            ])
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try FileManager.default.removeItem(at: directory)
        } else {
            Issue.record("held-cancellation fixture directory or owner was not recorded")
        }
    }
}
