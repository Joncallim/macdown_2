import Foundation

/// The parent-directory watcher is advisory, but windows need to know when
/// bounded event-driven recovery could not reinstall it so they can offer an
/// explicit Retry instead of silently remaining unmonitored.
public enum DocumentFileMonitorHealth: Sendable, Equatable {
    case healthy
    case failed
}

public actor DocumentFileMonitor {
    private let debounce: Duration
    private let watcher: any DocumentDirectoryWatching
    private let prober: any DocumentFileProbing
    private let sleeper: @Sendable (Duration) async -> Void
    private var generation: UInt = 0
    private var probeSequence: UInt = 0
    private var boundURL: URL?
    private var priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    private var handle: (any DocumentDirectoryWatcherHandle)?
    private var watcherHealthy = false
    /// A `.changed` event can arrive while the debounced `.parentVanished`
    /// recovery is pending. Keep this latch until a replacement watcher is
    /// actually installed so the later event cannot cancel parent recovery.
    private var parentRecoveryPending = false
    private var debounceTask: Task<Void, Never>?
    private var callback: (@Sendable (DocumentFileObservation) -> Void)?
    private var healthCallback: (@Sendable (DocumentFileMonitorHealth) -> Void)?

    public init(debounce: Duration = .milliseconds(150)) {
        self.init(
            debounce: debounce,
            watcher: LiveDocumentDirectoryWatcher(),
            prober: DocumentFileProbe(),
            sleeper: { duration in try? await Task.sleep(for: duration) }
        )
    }

    init(
        debounce: Duration,
        watcher: any DocumentDirectoryWatching,
        prober: any DocumentFileProbing,
        sleeper: @escaping @Sendable (Duration) async -> Void
    ) {
        self.debounce = debounce
        self.watcher = watcher
        self.prober = prober
        self.sleeper = sleeper
    }

    public func bind(
        to fileURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        onObservation: @escaping @Sendable (DocumentFileObservation) -> Void,
        onHealthChange: @escaping @Sendable (DocumentFileMonitorHealth) -> Void = { _ in }
    ) async throws {
        generation &+= 1
        probeSequence &+= 1
        let currentGeneration = generation
        let initialSequence = probeSequence
        cancelPending()
        handle?.cancel()
        handle = nil
        watcherHealthy = false
        parentRecoveryPending = false
        let standardized = fileURL.standardizedFileURL
        boundURL = standardized
        self.priorFileObjectID = priorFileObjectID
        callback = onObservation
        healthCallback = onHealthChange
        handle = try watcher.watch(standardized.deletingLastPathComponent()) { [weak self] signal in
            Task { await self?.received(signal, generation: currentGeneration) }
        }
        watcherHealthy = true
        healthCallback?(.healthy)
        let initial = await prober.observe(expectedURL: standardized, priorFileObjectID: priorFileObjectID)
        guard isCurrent(generation: currentGeneration, sequence: initialSequence) else { return }
        emit(initial, generation: currentGeneration, sequence: initialSequence)
    }

    public func updatePriorFileObjectID(
        _ id: PhysicalFileIdentity.FileObjectID?,
        expectedURL: URL
    ) {
        guard boundURL == expectedURL.standardizedFileURL else { return }
        priorFileObjectID = id
    }

    public func snapshotNow() async -> DocumentFileObservation {
        guard let boundURL else { return .missing(URL(fileURLWithPath: "")) }
        return await prober.observe(expectedURL: boundURL, priorFileObjectID: priorFileObjectID)
    }

    /// Attempts one event-driven watcher installation after a bounded recovery
    /// sequence has exhausted. Callers invoke this when the document becomes
    /// active or the user explicitly retries; it never creates idle polling.
    public func retryWatching() async throws {
        guard !watcherHealthy, let boundURL, let callback else { return }
        probeSequence &+= 1
        let currentGeneration = generation
        let sequence = probeSequence
        let replacement = try watcher.watch(boundURL.deletingLastPathComponent()) { [weak self] signal in
            Task { await self?.received(signal, generation: currentGeneration) }
        }
        guard isCurrent(generation: currentGeneration, sequence: sequence) else {
            replacement.cancel()
            return
        }
        handle?.cancel()
        handle = replacement
        watcherHealthy = true
        healthCallback?(.healthy)
        let initial = await prober.observe(expectedURL: boundURL, priorFileObjectID: priorFileObjectID)
        guard isCurrent(generation: currentGeneration, sequence: sequence) else { return }
        self.callback = callback
        emit(initial, generation: currentGeneration, sequence: sequence)
    }

    public func cancel() {
        generation &+= 1
        probeSequence &+= 1
        cancelPending()
        handle?.cancel()
        handle = nil
        watcherHealthy = false
        parentRecoveryPending = false
        callback = nil
        healthCallback = nil
        boundURL = nil
        priorFileObjectID = nil
    }

    private func received(_ signal: DocumentDirectorySignal, generation: UInt) {
        guard generation == self.generation, boundURL != nil else { return }
        if signal == .parentVanished {
            parentRecoveryPending = true
        }
        probeSequence &+= 1
        let currentSequence = probeSequence
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            await sleeper(debounce)
            guard !Task.isCancelled else { return }
            await probeAfterSignal(
                generation: generation,
                sequence: currentSequence
            )
        }
    }

    private func probeAfterSignal(
        generation: UInt,
        sequence: UInt
    ) async {
        guard isCurrent(generation: generation, sequence: sequence), let boundURL else { return }
        let first = await prober.observe(expectedURL: boundURL, priorFileObjectID: priorFileObjectID)
        guard !Task.isCancelled, isCurrent(generation: generation, sequence: sequence) else { return }
        if case .missing = first {
            await sleeper(.milliseconds(75))
            guard !Task.isCancelled, isCurrent(generation: generation, sequence: sequence) else { return }
            let confirmed = await prober.observe(expectedURL: boundURL, priorFileObjectID: priorFileObjectID)
            guard !Task.isCancelled, isCurrent(generation: generation, sequence: sequence) else { return }
            emit(confirmed, generation: generation, sequence: sequence)
        } else {
            emit(first, generation: generation, sequence: sequence)
        }
        if parentRecoveryPending {
            watcherHealthy = false
            await reinstallWatcherIfCurrent(generation: generation, sequence: sequence)
        }
    }

    private func emit(_ observation: DocumentFileObservation, generation: UInt, sequence: UInt) {
        guard isCurrent(generation: generation, sequence: sequence) else { return }
        if case let .available(snapshot) = observation {
            priorFileObjectID = snapshot.revision.fileObjectID
        }
        callback?(observation)
    }

    private func cancelPending() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func isCurrent(generation: UInt, sequence: UInt) -> Bool {
        generation == self.generation && sequence == probeSequence && boundURL != nil
    }

    private func reinstallWatcherIfCurrent(generation: UInt, sequence: UInt) async {
        guard isCurrent(generation: generation, sequence: sequence), let boundURL else { return }
        // The parent may be recreated well after its rename notification. A
        // bounded exponential retry keeps monitoring alive without converting
        // the monitor into an unbounded polling loop.
        for attempt in 0 ..< 4 {
            if attempt > 0 {
                await sleeper(.milliseconds(250 * (1 << (attempt - 1))))
            }
            guard isCurrent(generation: generation, sequence: sequence) else { return }
            do {
                let replacement = try watcher.watch(boundURL.deletingLastPathComponent()) { [weak self] signal in
                    Task { await self?.received(signal, generation: generation) }
                }
                guard isCurrent(generation: generation, sequence: sequence) else {
                    replacement.cancel()
                    return
                }
                handle?.cancel()
                handle = replacement
                watcherHealthy = true
                parentRecoveryPending = false
                healthCallback?(.healthy)
                // A replaced directory watcher cannot report the transition
                // that made its parent observable again. Probe once under a
                // fresh sequence so a file which reappeared before the new
                // watcher was armed is still reconciled. The sequence bump
                // also prevents the earlier parent-vanished probe from
                // publishing after this replacement probe.
                probeSequence &+= 1
                let replacementSequence = probeSequence
                let observation = await prober.observe(
                    expectedURL: boundURL,
                    priorFileObjectID: priorFileObjectID
                )
                guard isCurrent(generation: generation, sequence: replacementSequence) else { return }
                emit(observation, generation: generation, sequence: replacementSequence)
                return
            } catch {
                continue
            }
        }
        guard isCurrent(generation: generation, sequence: sequence) else { return }
        watcherHealthy = false
        healthCallback?(.failed)
    }
}
