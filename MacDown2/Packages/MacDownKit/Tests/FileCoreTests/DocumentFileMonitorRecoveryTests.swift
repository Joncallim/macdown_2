@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor parent recovery")
struct DocumentFileMonitorRecoveryTests {
    @Test func replacementWatcherProbesAReappearedFileWithoutAnotherEvent() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/reappearance-without-event.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let replacement = snapshot("replacement", at: fileURL)
        // The new watcher has no event for the already-reappeared file. Its
        // installation probe must nevertheless publish the replacement.
        let prober = ScriptedProber([
            .available(initial),
            .missing(fileURL),
            .missing(fileURL),
            .available(replacement),
        ])
        let recorder = MonitorRecoveryRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            Task { await recorder.append(observation) }
        }
        await waitUntil { await recorder.count == 1 }

        watcher.signal(.parentVanished)

        await waitUntil { await recorder.count == 3 }
        #expect(await recorder.values == [.available(initial), .missing(fileURL), .available(replacement)])
        #expect(await prober.callCount == 4)
    }

    @Test func parentVanishedLatchSurvivesAChangedEventDuringDebounce() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/parent-latch.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([
            .available(initial), .missing(fileURL), .missing(fileURL), .available(recovered),
        ])
        let recorder = MonitorRecoveryRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            Task { await recorder.append(observation) }
        }
        await waitUntil { await recorder.count == 1 }

        watcher.signal(.parentVanished)
        watcher.signal(.changed)

        await waitUntil { watcher.watchedDirectories.count == 2 }
        #expect(await recorder.values.last == .available(recovered))
    }

    @Test func parentVanishedReinstallsTheDirectoryWatcherAfterTheProbe() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/recreated-parent.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let afterRecreate = snapshot("after", at: fileURL)
        let prober = ScriptedProber([
            .available(initial),
            .available(afterRecreate),
            .available(afterRecreate),
        ])
        let recorder = MonitorRecoveryRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            Task { await recorder.append(observation) }
        }
        await waitUntil { await recorder.count == 1 }

        watcher.signal(.parentVanished)

        await waitUntil { await recorder.count == 3 }
        await waitUntil { watcher.watchedDirectories.count == 2 }
        #expect(watcher.cancelCount == 1)
    }

    @Test func parentRecoveryRetriesBeyondTheInitialQuarterSecondWindow() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/late-parent.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(recovered)])
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { _ in }

        watcher.failNextWatchAttempts(2)
        watcher.signal(.parentVanished)

        await waitUntil { watcher.watchedDirectories.count == 2 }
        #expect(watcher.failedWatchCount == 2)
    }

    @Test func exhaustedParentRecoveryCanBeExplicitlyRetriedOnActivation() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/retry-after-backoff.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(recovered)])
        let health = HealthRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(
            to: fileURL,
            priorFileObjectID: nil,
            onObservation: { _ in },
            onHealthChange: { value in
                health.append(value)
            }
        )

        watcher.failNextWatchAttempts(4)
        watcher.signal(.parentVanished)
        await waitUntil { watcher.failedWatchCount == 4 }
        await waitUntil { health.contains(.failed) }

        try await monitor.retryWatching()
        await waitUntil { health.last == .healthy }

        #expect(watcher.watchedDirectories.count == 2)
        #expect(await prober.callCount == 3)
        #expect(health.last == .healthy)
    }
}

private actor MonitorRecoveryRecorder {
    private(set) var values: [DocumentFileObservation] = []

    var count: Int {
        values.count
    }

    func append(_ observation: DocumentFileObservation) {
        values.append(observation)
    }
}
