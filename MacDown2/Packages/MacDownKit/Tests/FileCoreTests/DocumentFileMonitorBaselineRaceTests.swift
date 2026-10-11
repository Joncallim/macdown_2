@testable import FileCore
import Foundation
import Testing

/// Cross-feature review (2026-10-11), F2: `updateBaseline` changed the monitor's decoding policy and identity without
/// invalidating a probe already in flight, so the first bind's initial probe (taken under the OLD policy) was still
/// published after a Save with Encoding, reporting a correctly saved file as undecodable.
private actor HeldFirstProber: DocumentFileProbing {
    private(set) var policies: [FileDecodingPolicy] = []
    private var heldFirst: CheckedContinuation<Void, Never>?
    private let oldResult: DocumentFileObservation
    private let newResult: DocumentFileObservation

    init(old: DocumentFileObservation, new: DocumentFileObservation) {
        oldResult = old
        newResult = new
    }

    var callCount: Int {
        policies.count
    }

    func observe(
        expectedURL _: URL,
        priorFileObjectID _: PhysicalFileIdentity.FileObjectID?,
        decoding: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        policies.append(decoding)
        guard policies.count == 1 else { return newResult }
        await withCheckedContinuation { heldFirst = $0 }
        return oldResult
    }

    func releaseFirst() {
        heldFirst?.resume()
        heldFirst = nil
    }
}

struct DocumentFileMonitorBaselineRaceTests {
    @Test func aBaselineChangeWhileTheInitialProbeIsInFlightDiscardsItsStaleAnswerAndPublishesAFreshOne() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/baseline-race.md")
        let stale = DocumentFileObservation.unavailable(url, .readFailed("decoded under the old policy"))
        let fresh = DocumentFileObservation.available(snapshot("fresh", at: url))
        let prober = HeldFirstProber(old: stale, new: fresh)
        let recorder = ObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero, watcher: MonitorWatcher(), prober: prober, sleeper: { _ in await Task.yield() }
        )

        let bind = Task {
            try await monitor.bind(to: url, priorFileObjectID: nil, decoding: .automatic) { recorder.append($0) }
        }
        await waitUntil { await prober.callCount == 1 } // the initial probe is suspended under `.automatic`

        await monitor.updateBaseline(priorFileObjectID: nil, decoding: .explicit(.isoLatin1), expectedURL: url)
        await prober.releaseFirst()
        try await bind.value

        await waitUntil { recorder.count >= 1 }
        #expect(recorder.values == [fresh], "the stale initial answer must not be published; the fresh one must")
        #expect(await prober.policies == [.automatic, .explicit(.isoLatin1)])
    }

    @Test func anUnchangedBaselineDoesNotProbeAgain() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/baseline-noop.md")
        let fresh = DocumentFileObservation.available(snapshot("x", at: url))
        let prober = HeldFirstProber(old: fresh, new: fresh)
        let monitor = DocumentFileMonitor(
            debounce: .zero, watcher: MonitorWatcher(), prober: prober, sleeper: { _ in await Task.yield() }
        )
        let bind = Task { try await monitor.bind(to: url, priorFileObjectID: nil, decoding: .automatic) { _ in } }
        await waitUntil { await prober.callCount == 1 }
        await prober.releaseFirst()
        try await bind.value

        await monitor.updateBaseline(priorFileObjectID: nil, decoding: .automatic, expectedURL: url)

        #expect(await prober.callCount == 1)
    }

    /// Cross-boundary review (2026-10-12), F1 (P1): the controller calls `updateBaseline` from the reconcile of each
    /// probe result. A conflicted dirty document keeps its OLD revision while the file's identity is the new one, so
    /// every probe result fed back a different identity; probing on identity change then looped forever (hundreds of
    /// full-file reads/hashes, recovery writes and generation bumps per external change).
    @Test func anIdentityOnlyBaselineChangeNeverProbes() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/baseline-loop.md")
        let fresh = DocumentFileObservation.available(snapshot("x", at: url))
        let prober = HeldFirstProber(old: fresh, new: fresh)
        let monitor = DocumentFileMonitor(
            debounce: .zero, watcher: MonitorWatcher(), prober: prober, sleeper: { _ in await Task.yield() }
        )
        let bind = Task { try await monitor.bind(to: url, priorFileObjectID: nil, decoding: .automatic) { _ in } }
        await waitUntil { await prober.callCount == 1 }
        await prober.releaseFirst()
        try await bind.value
        let sequenceBefore = await monitor.currentRequestGeneration()

        for index in 0 ..< 50 { // the controller feeding back alternating identities, as a conflicted document does
            let identity = PhysicalFileIdentity.FileObjectID(volume: "v", file: index.isMultiple(of: 2) ? "old" : "new")
            await monitor.updateBaseline(priorFileObjectID: identity, decoding: .automatic, expectedURL: url)
        }

        #expect(await prober.callCount == 1, "no probe may be started by an identity-only update")
        #expect(await monitor.currentRequestGeneration() == sequenceBefore, "and in-flight probes stay valid")
    }
}
