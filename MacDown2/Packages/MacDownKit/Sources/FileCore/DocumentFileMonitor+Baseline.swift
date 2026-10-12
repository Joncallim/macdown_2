import Foundation

public extension DocumentFileMonitor {
    /// Updates the baseline identity and decoding policy in one actor turn so
    /// no probe can observe one without the other.
    ///
    /// A probe already in flight captured the OLD decoding policy (the initial probe of `bind`, or one started by a
    /// watcher signal), so a Save with Encoding made meanwhile would be reported undecodable. A real POLICY change
    /// therefore invalidates in-flight probes (new request sequence) and publishes a fresh probe taken under the new
    /// policy, so no observation is lost.
    ///
    /// An identity-only change (the file object after a save, or the controller echoing a conflicted document's old
    /// revision) updates the stored baseline and, only if a probe is in flight, retires it and probes again: that
    /// probe may have read the file before the save and would be published as current. With nothing in flight it must
    /// NOT probe: the controller feeds this call from the reconcile of every probe result (which arrives after the
    /// emit), so a probe-per-identity-change loops forever whenever the document's revision and the file's identity
    /// disagree (a dirty document in conflict).
    func updateBaseline(
        priorFileObjectID id: PhysicalFileIdentity.FileObjectID?,
        decoding policy: FileDecodingPolicy,
        expectedURL: URL
    ) async {
        guard let bound = boundURL, bound == expectedURL.standardizedFileURL else { return }
        let policyChanged = policy != decoding
        priorFileObjectID = id
        decoding = policy
        guard policyChanged || probesInFlight > 0 else { return }
        probeSequence &+= 1
        let currentGeneration = generation
        let sequence = probeSequence
        let observation = await trackedObserve(expectedURL: bound, priorFileObjectID: id, decoding: policy)
        emit(observation, generation: currentGeneration, sequence: sequence)
    }

    /// `prober.observe` for a probe whose result is emitted, counted while suspended.
    internal func trackedObserve(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        decoding: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        probesInFlight += 1
        defer { probesInFlight -= 1 }
        return await prober.observe(expectedURL: expectedURL, priorFileObjectID: priorFileObjectID, decoding: decoding)
    }
}
