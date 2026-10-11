import Foundation

public extension DocumentFileMonitor {
    /// Updates the baseline identity and decoding policy in one actor turn so
    /// no probe can observe one without the other.
    ///
    /// A probe already in flight captured the OLD identity and policy (the initial probe of `bind`, or one started by a
    /// watcher signal), so its answer would be stale: a Save with Encoding made while the first probe was suspended
    /// would otherwise be reported undecodable. A real change therefore invalidates in-flight probes (new request
    /// sequence) and publishes a fresh probe taken under the new baseline, so no observation is lost.
    func updateBaseline(
        priorFileObjectID id: PhysicalFileIdentity.FileObjectID?,
        decoding policy: FileDecodingPolicy,
        expectedURL: URL
    ) async {
        guard let bound = boundURL, bound == expectedURL.standardizedFileURL else { return }
        guard id != priorFileObjectID || policy != decoding else { return }
        priorFileObjectID = id
        decoding = policy
        probeSequence &+= 1
        let currentGeneration = generation
        let sequence = probeSequence
        let observation = await prober.observe(expectedURL: bound, priorFileObjectID: id, decoding: policy)
        emit(observation, generation: currentGeneration, sequence: sequence)
    }
}
