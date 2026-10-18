import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture cleanup safety")
struct TextFilterFixtureCleanupSafetyTests {
    private enum FixtureFailure: Error {
        case expected
    }

    private actor CleanupProbe {
        private(set) var cleanupJoinStarted = false
        private(set) var cleanupCallerFinishedCount = 0
        private(set) var taskFinished = false

        func recordCleanupJoinStarted() {
            cleanupJoinStarted = true
        }

        func recordCleanupCallerFinished() {
            cleanupCallerFinishedCount += 1
        }

        func recordTaskFinished() {
            taskFinished = true
        }
    }

    private final class BlockingCancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var phases: [(TextFilterFixtures.CleanupPhase, ContinuousClock.Instant)] = []

        func record(_ phase: TextFilterFixtures.CleanupPhase) {
            let instant = ContinuousClock.now
            lock.lock()
            phases.append((phase, instant))
            lock.unlock()
        }

        func timeline(from start: ContinuousClock.Instant) -> String {
            lock.lock()
            defer { lock.unlock() }
            return phases.map { "\($0.0.rawValue)=\(start.duration(to: $0.1))" }.joined(separator: ", ")
        }

        var isFinished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }

        func blockFor(_ duration: useconds_t) {
            usleep(duration)
            lock.lock()
            finished = true
            lock.unlock()
        }
    }

    private actor CancellationAwareJoinProbe {
        private(set) var joinStarted = false
        private(set) var joinFinished = false

        func recordJoinStarted() {
            joinStarted = true
        }

        func recordJoinFinished() {
            joinFinished = true
        }
    }

    @Test func concurrentCleanupCallersShareTheSameJoinTask() async throws {
        let probe = CleanupProbe()
        let owner = TextFilterFixtures.TaskOwner()
        try await owner.registerCleanup(
            cancel: {},
            join: {
                await probe.recordCleanupJoinStarted()
                try? await Task.sleep(for: .milliseconds(150))
                return .completed(nil)
            }
        )

        let first = Task {
            let joinTask = await owner.cancelAllAndCreateJoinTask()
            _ = await joinTask.value
            await probe.recordCleanupCallerFinished()
        }
        let second = Task {
            let joinTask = await owner.cancelAllAndCreateJoinTask()
            _ = await joinTask.value
            await probe.recordCleanupCallerFinished()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            if await probe.cleanupJoinStarted {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await probe.cleanupJoinStarted)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await probe.cleanupCallerFinishedCount == 0)

        _ = await first.value
        _ = await second.value
        #expect(await probe.cleanupCallerFinishedCount == 2)
    }

    @Test func nonCooperativeCleanupUsesAWatchdogAndPreservesDirectoryWhenUnresolved() async throws {
        let probe = CleanupProbe()
        var observedDirectory: URL?

        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(cleanupTimeout: .milliseconds(25)) { directory, owner in
                    observedDirectory = directory
                    _ = try await owner.start {
                        usleep(200_000)
                        await probe.recordTaskFinished()
                    }
                    throw FixtureFailure.expected
                }
            Issue.record("expected fixture cleanup to exceed its watchdog")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            guard case let .cleanupTimedOut(primary, timeout) = error else {
                Issue.record("unexpected fixture cleanup error: \(error)")
                return
            }
            #expect(primary?.contains("expected") == true)
            #expect(timeout == .milliseconds(25))
        }

        let directory = try #require(observedDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(await !probe.taskFinished)

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await !probe.taskFinished, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await probe.taskFinished)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [Duration.zero, .milliseconds(200)])
    func cleanupDeadlineIncludesBlockingCancellationDispatch(setupDelay: Duration) async throws {
        let probe = BlockingCancellationProbe()
        var observedDirectory: URL?
        let fixtureStarted = ContinuousClock.now
        var cleanupStarted: ContinuousClock.Instant?
        let observeCleanup: @Sendable (TextFilterFixtures.CleanupPhase) -> Void = { probe.record($0) }

        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(
                    cleanupTimeout: .milliseconds(25), cleanupObserver: observeCleanup
                ) { directory, owner in
                    observedDirectory = directory
                    if setupDelay > .zero {
                        try await Task.sleep(for: setupDelay)
                    }
                    try await owner.registerCleanup(
                        cancel: { probe.blockFor(200_000) },
                        join: { .completed(nil) }
                    )
                    // Keep a separate cleanup interval for diagnostics, including cancellation dispatch.
                    // The zero-delay case also retains the original whole-call 150 ms assertion below.
                    cleanupStarted = .now
                }
            Issue.record("expected cleanup watchdog to include cancellation dispatch")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            guard case let .cleanupTimedOut(primary, timeout) = error else {
                Issue.record("unexpected fixture cleanup error: \(error)")
                return
            }
            #expect(primary == nil)
            #expect(timeout == .milliseconds(25))
        }

        let started = try #require(cleanupStarted)
        let finished = ContinuousClock.now
        let setupElapsed = fixtureStarted.duration(to: started)
        let cleanupElapsed = started.duration(to: finished)
        let timeline = probe.timeline(from: started)
        print("CLEANUP_TIMELINE setup=\(setupElapsed), cleanup=\(cleanupElapsed), \(timeline)")
        if setupDelay == .zero {
            #expect(
                fixtureStarted.duration(to: finished) < .milliseconds(150),
                "whole fixture call: setup \(setupElapsed), cleanup \(cleanupElapsed); \(timeline)"
            )
        }
        #expect(
            cleanupElapsed < .milliseconds(150),
            "fixture setup took \(setupElapsed); cleanup includes cancellation dispatch; \(timeline)"
        )
        let directory = try #require(observedDirectory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        try await finishBlockingCancellation(probe, directory: directory)
    }

    private func finishBlockingCancellation(_ probe: BlockingCancellationProbe, directory: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !probe.isFinished, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(probe.isFinished)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func unresolvedCleanupPreservesOrdinaryCleanupFailures() async throws {
        var observedDirectory: URL?

        do {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                observedDirectory = directory
                try await owner.registerCleanup(
                    cancel: {},
                    join: { .completed("important cleanup failure") }
                )
                try await owner.registerCleanup(
                    cancel: {},
                    join: { .unresolved("worker still running") }
                )
            }
            Issue.record("expected unresolved cleanup")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            guard case let .cleanupUnresolved(_, reasons) = error else {
                Issue.record("unexpected fixture cleanup error: \(error)")
                return
            }
            #expect(reasons.contains("worker still running"))
            #expect(reasons.contains("cleanup failure: important cleanup failure"))
        }

        if let observedDirectory {
            try? FileManager.default.removeItem(at: observedDirectory)
        }
    }

    @Test func cleanupTimeoutCancelsTheInnerAggregateJoinAndItsObserverCanFinish() async throws {
        let probe = CancellationAwareJoinProbe()
        var observedDirectory: URL?

        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(cleanupTimeout: .milliseconds(25)) { directory, owner in
                    observedDirectory = directory
                    try await owner.registerCleanup(
                        cancel: {},
                        join: {
                            await probe.recordJoinStarted()
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .milliseconds(10))
                            }
                            await probe.recordJoinFinished()
                            return .unresolved("aggregate join was cancelled")
                        }
                    )
                }
            Issue.record("expected cleanup watchdog to cancel the aggregate join")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            guard case .cleanupTimedOut = error else {
                Issue.record("unexpected fixture cleanup error: \(error)")
                return
            }
        }

        #expect(await probe.joinStarted)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await !probe.joinFinished, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await probe.joinFinished)

        let directory = try #require(observedDirectory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        try? FileManager.default.removeItem(at: directory)
    }
}
