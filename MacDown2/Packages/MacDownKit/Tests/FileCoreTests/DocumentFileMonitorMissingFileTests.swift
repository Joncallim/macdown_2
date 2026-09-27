@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor missing-file recovery")
struct DocumentFileMonitorMissingFileTests {
    @Test func missingFileKeepsParentWatchAndRearmsFileWatchWhenRecreated() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/recreated.md")
        let watcher = MonitorWatcher()
        watcher.failNextFileWatchAttempts(1)
        let replacement = snapshot("recreated", at: fileURL)
        let prober = ScriptedProber([.missing(fileURL), .available(replacement)])
        let recorder = MissingObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )

        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }
        #expect(recorder.values == [.missing(fileURL)])
        #expect(watcher.watchedDirectories.count == 1)
        #expect(watcher.fileWatchCount == 0)

        watcher.signal(.changed)
        await waitUntil {
            guard watcher.fileWatchCount == 1 else { return false }
            return recorder.count == 2
        }
        #expect(recorder.values == [.missing(fileURL), .available(replacement)])
    }
}

/// Lock-based, synchronously-appending recorder -- see
/// `DocumentFileMonitorTests.swift`'s own `ObservationRecorder` doc comment
/// for why this isn't an actor fed via `Task { await recorder.append(...) }`.
private final class MissingObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [DocumentFileObservation] = []

    var values: [DocumentFileObservation] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValues.count
    }

    func append(_ observation: DocumentFileObservation) {
        lock.lock()
        storedValues.append(observation)
        lock.unlock()
    }
}
