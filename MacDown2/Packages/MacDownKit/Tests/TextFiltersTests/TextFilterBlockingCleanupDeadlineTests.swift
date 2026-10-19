import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter blocking cleanup deadline")
struct TextFilterBlockingCleanupDeadlineTests {
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
            if case let .cleanupTimedOut(primary, timeout) = error {
                #expect(primary == nil)
                #expect(timeout == .milliseconds(25))
            } else {
                Issue.record("unexpected fixture cleanup error: \(error)")
            }
        }

        assertCleanupBounds(
            setupDelay: setupDelay,
            fixtureStarted: fixtureStarted,
            cleanupStarted: cleanupStarted,
            probe: probe
        )
        if let directory = observedDirectory {
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try await finishBlockingCancellation(probe, directory: directory)
        } else {
            Issue.record("blocking-cancellation fixture directory was not recorded")
        }
    }

    private func finishBlockingCancellation(_ probe: BlockingCancellationProbe, directory: URL) async throws {
        let joinTask = Task.detached {
            probe.waitForFinished(timeout: .now() + .seconds(2))
        }
        #expect(await joinTask.value, "blocking cancellation callback completed before fixture removal")
        try? FileManager.default.removeItem(at: directory)
    }

    private func assertCleanupBounds(
        setupDelay: Duration,
        fixtureStarted: ContinuousClock.Instant,
        cleanupStarted: ContinuousClock.Instant?,
        probe: BlockingCancellationProbe
    ) {
        guard let started = cleanupStarted else {
            Issue.record("cleanup interval start was not captured")
            return
        }
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
    }
}
