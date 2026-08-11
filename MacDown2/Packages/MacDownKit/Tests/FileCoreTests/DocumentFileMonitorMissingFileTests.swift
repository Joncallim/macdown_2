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
            Task { await recorder.append(observation) }
        }
        await waitUntil { await recorder.count == 1 }
        #expect(await recorder.values == [.missing(fileURL)])
        #expect(watcher.watchedDirectories.count == 1)
        #expect(watcher.fileWatchCount == 0)

        watcher.signal(.changed)
        await waitUntil {
            guard watcher.fileWatchCount == 1 else { return false }
            return await recorder.count == 2
        }
        #expect(await recorder.values == [.missing(fileURL), .available(replacement)])
    }
}

private actor MissingObservationRecorder {
    private(set) var values: [DocumentFileObservation] = []

    var count: Int {
        values.count
    }

    func append(_ observation: DocumentFileObservation) {
        values.append(observation)
    }
}
