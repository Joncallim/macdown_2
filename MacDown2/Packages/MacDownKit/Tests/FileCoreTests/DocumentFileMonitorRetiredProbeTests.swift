@testable import FileCore
import Foundation
import Testing

private actor HeldRetiredProbeProber: DocumentFileProbing {
    private(set) var calls = 0
    private var held: CheckedContinuation<Void, Never>?
    let result: DocumentFileObservation
    init(result: DocumentFileObservation) {
        self.result = result
    }

    func observe(expectedURL _: URL, priorFileObjectID _: PhysicalFileIdentity.FileObjectID?,
                 decoding _: FileDecodingPolicy) async -> DocumentFileObservation {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { held = $0 }
        }
        return result
    }

    func release() {
        held?.resume(); held = nil
    }
}

/// Final-head review (ebf6445e) F1: #428 counted probes that were already RETIRED, so while a slow one stayed suspended
/// every controller echo started another probe and the #415 loop returned.
struct DocumentFileMonitorRetiredProbeTests {
    /// A RETIRED probe that is still suspended keeps `probesInFlight > 0`, so the controller's echo of a conflicted
    /// document's old identity (fed back on every emission) re-probes on every emission: the #415 loop returns for
    /// as long as the retired probe stays suspended.
    @Test func aRetiredSlowProbeDoesNotReviveTheFeedbackLoop() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/retired-loop.md")
        let fresh = DocumentFileObservation.available(snapshot("x", at: url))
        let prober = HeldRetiredProbeProber(result: fresh)
        let monitor = DocumentFileMonitor(
            debounce: .zero, watcher: MonitorWatcher(), prober: prober, sleeper: { _ in await Task.yield() }
        )
        let old = PhysicalFileIdentity.FileObjectID(volume: "v", file: "old-conflicted-revision")
        let bind = Task {
            try await monitor.bind(to: url, priorFileObjectID: nil, decoding: .automatic) { _ in
                // The controller: reconcile keeps the conflicted document's OLD revision and echoes it back.
                Task { await monitor.updateBaseline(priorFileObjectID: old, decoding: .automatic, expectedURL: url) }
            }
        }
        while await prober.calls < 1 {
            await Task.yield()
        }
        // One identity update (e.g. a save's new file object) while the bind's probe is in flight retires it.
        await monitor.updateBaseline(
            priorFileObjectID: .init(volume: "v", file: "saved"), decoding: .automatic, expectedURL: url
        )
        try await Task.sleep(for: .milliseconds(300))
        let probes = await prober.calls
        await prober.release()
        _ = try? await bind.value
        #expect(probes <= 3, "probes started while the retired probe was suspended: \(probes)")
    }
}
