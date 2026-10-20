import Foundation
import LocalResourceAccess
import Preview

enum PreviewResourceAdmissionError: Error, Equatable {
    case limitExceeded
    case revoked
    case cancelled
}

/// A load binds one immutable grant. Its revocation bit survives actor ledger pruning, so a late caller cannot
/// recreate an old load by presenting its former ID after the last worker and payload have drained.
final class PreviewResourceLoad: @unchecked Sendable {
    let id = UUID()
    let grant: PreviewDirectoryGrantBacking
    let imageDecodeBudget = PreviewImageDecodeBudget()
    private let lock = NSLock()
    private var revoked = false

    init(grant: PreviewDirectoryGrantBacking) {
        self.grant = grant
    }

    var isRevoked: Bool {
        lock.withLock { revoked }
    }

    func revoke() {
        lock.withLock { revoked = true }
    }

    /// The revocation check and grant admission share one lock. A worker either enters before retirement and may
    /// drain, or observes retirement; it cannot start a new read in the gap between two separate checks.
    func acquireUse() -> PreviewDirectoryGrantBacking.Use? {
        lock.withLock {
            guard !revoked else { return nil }
            return grant.acquireUse()
        }
    }
}

/// The snapshot's app-owned bytes remain reserved until the last holder releases this object.
/// A retired load keeps its ledger while payloads or workers are still alive.
final class PreviewResourcePayload: @unchecked Sendable {
    let snapshot: ResourceSnapshot
    private let owner: PreviewResourceAdmission
    private let loadID: UUID

    init(snapshot: ResourceSnapshot, owner: PreviewResourceAdmission, loadID: UUID) {
        self.snapshot = snapshot
        self.owner = owner
        self.loadID = loadID
    }

    deinit {
        let byteCount = snapshot.bytes.count
        let owner = owner
        let loadID = loadID
        Task { await owner.releasePayload(loadID: loadID, byteCount: byteCount) }
    }
}

/// One app-wide admission service. Cancellation revokes delivery immediately; a running blocking read keeps its
/// worker slot and byte reservation until the syscall job really ends. All counters are actor-owned.
actor PreviewResourceAdmission {
    struct Status: Equatable {
        let activeWorkers: Int
        let queued: Int
        let reserved: Int
        let retained: Int
        let delivered: Int
    }

    struct GlobalStatus: Equatable {
        let reserved: Int
        let retained: Int
    }

    typealias ReadOperation = @Sendable (
        ResourceReference, DirectoryLease, ResourceCancellation
    ) throws -> ResourceSnapshot

    static let shared = PreviewResourceAdmission()
    static let resourceLimit = 16 * 1024 * 1024
    static let loadLimit = 64 * 1024 * 1024
    static let requestLimit = 512
    static let globalInputLimit = 128 * 1024 * 1024
    private static let globalWorkers = 4
    private static let contextWorkers = 2
    private static let contextQueueLimit = 32
    private static let globalQueueLimit = 128

    private struct Job {
        let context: PreviewResourceLoad
        let reference: ResourceReference
        let cancellation: ResourceCancellation
        let continuation: CheckedContinuation<PreviewResourcePayload, Error>
    }

    private struct Load {
        let context: PreviewResourceLoad
        var requests = 0
        var active = 0
        var queue: [UUID] = []
        var reserved = 0
        var retained = 0
        var delivered = 0
    }

    private let readOperation: ReadOperation
    private let settlementGate: (@Sendable () async -> Void)?
    private let inputLimit: Int
    private var loads: [UUID: Load] = [:]
    private var order: [UUID] = []
    private var nextContext = 0
    private var jobs: [UUID: Job] = [:]
    private var activeWorkers = 0
    private var globallyReserved = 0
    private var globallyRetained = 0
    private var settling: [UUID: UUID] = [:]

    func globalStatus() -> GlobalStatus {
        GlobalStatus(reserved: globallyReserved, retained: globallyRetained)
    }

    func status(for context: PreviewResourceLoad) -> Status? {
        guard let load = loads[context.id] else { return nil }
        return Status(
            activeWorkers: load.active, queued: load.queue.count,
            reserved: load.reserved, retained: load.retained, delivered: load.delivered
        )
    }

    init(
        inputLimit: Int = globalInputLimit,
        settlementGate: (@Sendable () async -> Void)? = nil,
        readOperation: @escaping ReadOperation = { reference, directory, cancellation in
            try ContainedResourceReader.read(
                reference, in: directory, maxBytes: resourceLimit, cancellation: cancellation
            )
        }
    ) {
        self.inputLimit = inputLimit
        self.settlementGate = settlementGate
        self.readOperation = readOperation
    }

    func read(
        _ reference: ResourceReference,
        in context: PreviewResourceLoad
    ) async throws -> PreviewResourcePayload {
        let jobID = UUID()
        let cancellation = ResourceCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    jobID: jobID,
                    job: Job(context: context, reference: reference,
                             cancellation: cancellation, continuation: continuation)
                )
            }
        } onCancel: {
            cancellation.cancel()
            Task { await self.cancel(jobID: jobID) }
        }
    }

    func retire(_ context: PreviewResourceLoad) {
        context.revoke()
        let loadID = context.id
        guard var load = loads[loadID] else { return }
        let queued = load.queue
        load.queue.removeAll()
        load.reserved -= queued.count * Self.resourceLimit
        globallyReserved -= queued.count * Self.resourceLimit
        loads[loadID] = load
        for jobID in queued {
            guard let job = jobs.removeValue(forKey: jobID) else { continue }
            job.cancellation.cancel()
            job.continuation.resume(throwing: PreviewResourceAdmissionError.revoked)
        }
        for job in jobs.values where job.context.id == loadID {
            job.cancellation.cancel()
        }
        prune(loadID: loadID)
        pump()
    }

    private func enqueue(jobID: UUID, job: Job) {
        guard !job.cancellation.isCancelled else {
            job.continuation.resume(throwing: PreviewResourceAdmissionError.cancelled)
            return
        }
        var load = loads[job.context.id] ?? Load(context: job.context)
        guard !job.context.isRevoked else {
            job.continuation.resume(throwing: PreviewResourceAdmissionError.revoked)
            return
        }
        let queuedTotal = loads.values.reduce(0) { $0 + $1.queue.count }
        guard load.requests < Self.requestLimit,
              load.queue.count < Self.contextQueueLimit,
              queuedTotal < Self.globalQueueLimit,
              load.delivered <= Self.loadLimit - Self.resourceLimit,
              load.reserved <= Self.loadLimit - Self.resourceLimit - load.delivered,
              Self.resourceLimit <= inputLimit,
              globallyReserved <= inputLimit - Self.resourceLimit - globallyRetained
        else {
            job.continuation.resume(throwing: PreviewResourceAdmissionError.limitExceeded)
            return
        }
        load.requests += 1
        load.reserved += Self.resourceLimit
        globallyReserved += Self.resourceLimit
        load.queue.append(jobID)
        if loads[job.context.id] == nil {
            order.append(job.context.id)
        }
        loads[job.context.id] = load
        jobs[jobID] = job
        pump()
    }

    private func cancel(jobID: UUID) {
        guard let job = jobs[jobID], var load = loads[job.context.id] else { return }
        job.cancellation.cancel()
        guard let queueIndex = load.queue.firstIndex(of: jobID) else { return }
        load.queue.remove(at: queueIndex)
        load.reserved -= Self.resourceLimit
        globallyReserved -= Self.resourceLimit
        loads[job.context.id] = load
        jobs.removeValue(forKey: jobID)
        job.continuation.resume(throwing: PreviewResourceAdmissionError.cancelled)
        prune(loadID: job.context.id)
        pump()
    }

    private func pump() {
        while activeWorkers < Self.globalWorkers, !order.isEmpty {
            var selected: (index: Int, loadID: UUID)?
            for offset in 0 ..< order.count {
                let index = (nextContext + offset) % order.count
                let loadID = order[index]
                if let load = loads[loadID], !load.context.isRevoked,
                   !load.queue.isEmpty, load.active < Self.contextWorkers {
                    selected = (index, loadID)
                    break
                }
            }
            guard let selected, var load = loads[selected.loadID] else { return }
            nextContext = (selected.index + 1) % order.count
            let jobID = load.queue.removeFirst()
            load.active += 1
            activeWorkers += 1
            loads[selected.loadID] = load
            guard let job = jobs[jobID] else { preconditionFailure("queued job vanished") }
            let operation = readOperation
            let settlementGate = settlementGate
            Task.detached(priority: .utility) {
                var deliveredPayload: PreviewResourcePayload?
                do {
                    let result = Result { () throws -> ResourceSnapshot in
                        guard !job.cancellation.isCancelled else { throw PreviewResourceAdmissionError.cancelled }
                        guard let use = job.context.acquireUse()
                        else { throw PreviewResourceAdmissionError.revoked }
                        return try withExtendedLifetime(use) {
                            try operation(job.reference, use.documentDirectory, job.cancellation)
                        }
                    }
                    deliveredPayload = await self.complete(jobID: jobID, result: result)
                }
                // A fast caller may drop its payload before this worker sheds its own successful Result.
                // Keep the very same charged wrapper alive through that handoff.
                withExtendedLifetime(deliveredPayload) {}
                deliveredPayload = nil
                await settlementGate?()
                // The local Result (including a rejected successful snapshot) has left scope. Only now may its
                // original input reservation be refunded and another blocking read admitted.
                await self.settled(jobID: jobID)
            }
        }
    }
}

extension PreviewResourceAdmission {
    private func complete(jobID: UUID, result: Result<ResourceSnapshot, Error>) -> PreviewResourcePayload? {
        guard let job = jobs.removeValue(forKey: jobID), var load = loads[job.context.id] else {
            preconditionFailure("running job lost its accounting")
        }
        precondition(activeWorkers > 0 && load.active > 0 && load.reserved >= Self.resourceLimit)
        activeWorkers -= 1
        load.active -= 1
        switch result {
        case let .success(snapshot) where !job.cancellation.isCancelled && !job.context.isRevoked
            && snapshot.bytes.count <= Self.resourceLimit:
            let byteCount = snapshot.bytes.count
            load.reserved -= Self.resourceLimit
            load.retained += byteCount
            load.delivered += byteCount
            globallyReserved -= Self.resourceLimit
            globallyRetained += byteCount
            loads[job.context.id] = load
            let payload = PreviewResourcePayload(
                snapshot: snapshot, owner: self, loadID: job.context.id
            )
            job.continuation.resume(returning: payload)
            prune(loadID: job.context.id)
            pump()
            return payload
        default:
            settling[jobID] = job.context.id
            loads[job.context.id] = load
            if job.cancellation.isCancelled {
                job.continuation.resume(throwing: PreviewResourceAdmissionError.cancelled)
            } else if job.context.isRevoked {
                job.continuation.resume(throwing: PreviewResourceAdmissionError.revoked)
            } else if case let .failure(error) = result {
                job.continuation.resume(throwing: error)
            } else {
                job.continuation.resume(throwing: PreviewResourceAdmissionError.limitExceeded)
            }
        }
        prune(loadID: job.context.id)
        pump()
        return nil
    }

    private func settled(jobID: UUID) {
        guard let loadID = settling.removeValue(forKey: jobID), var load = loads[loadID] else { return }
        precondition(load.reserved >= Self.resourceLimit)
        load.reserved -= Self.resourceLimit
        globallyReserved -= Self.resourceLimit
        loads[loadID] = load
        prune(loadID: loadID)
        pump()
    }

    fileprivate func releasePayload(loadID: UUID, byteCount: Int) {
        guard var load = loads[loadID] else { preconditionFailure("payload lost its ledger") }
        precondition(byteCount <= load.retained)
        load.retained -= byteCount
        globallyRetained -= byteCount
        loads[loadID] = load
        prune(loadID: loadID)
    }

    private func prune(loadID: UUID) {
        guard let load = loads[loadID], load.context.isRevoked,
              load.active == 0, load.queue.isEmpty, load.retained == 0,
              load.reserved == 0 else { return }
        loads.removeValue(forKey: loadID)
        if let index = order.firstIndex(of: loadID) {
            order.remove(at: index)
            if order.isEmpty {
                nextContext = 0
            } else if index < nextContext {
                nextContext -= 1
            } else {
                nextContext %= order.count
            }
        }
    }
}
