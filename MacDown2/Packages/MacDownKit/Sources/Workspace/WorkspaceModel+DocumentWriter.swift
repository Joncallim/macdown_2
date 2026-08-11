import FileCore
import Foundation

actor DocumentWriter {
    private let onRequestQueued: (@Sendable () -> Void)?
    private var acceptedLineage: [DocumentKey: [RevisionLineageKey: FileRevision]] = [:]
    /// Inputs captured by requests which have entered a document lane but may
    /// not yet have selected their conditional-write baseline. Keep lineage
    /// only while one of these callers can still need to follow it.
    private var pendingSources: [DocumentKey: [RevisionLineageKey: Int]] = [:]
    /// A write result remains a live lineage consumer until its owning
    /// WorkspaceModel has applied or discarded it. Releasing a lane is not an
    /// acknowledgement: another save can enter between those two events.
    private var unacknowledgedResults: [UUID: PendingWriteResult] = [:]
    private var occupiedLanes: Set<DocumentKey> = []
    private var laneWaiters: [DocumentKey: [CheckedContinuation<Void, Never>]] = [:]

    init(onRequestQueued: (@Sendable () -> Void)? = nil) {
        self.onRequestQueued = onRequestQueued
    }

    func save(_ document: FileDocument) async throws(FileStoreError) -> DocumentWriteResult {
        let key = DocumentKey(document)
        let sourceRevision = document.lastKnownRevision
        registerPendingSource(sourceRevision, for: key)
        await acquireLane(for: key)
        let expectedRevision = baseline(for: document)
        do {
            let saved = try await write(document, expectedRevision: expectedRevision)
            record(saved, source: sourceRevision, expected: expectedRevision)
            let resultID = UUID()
            unacknowledgedResults[resultID] = PendingWriteResult(
                key: key,
                sourceRevision: sourceRevision,
                expectedRevision: expectedRevision
            )
            releaseLane(for: key)
            return DocumentWriteResult(
                id: resultID,
                document: saved,
                sourceRevision: sourceRevision,
                expectedRevision: expectedRevision
            )
        } catch {
            finishRequest(sourceRevision, for: key)
            releaseLane(for: key)
            throw error
        }
    }

    func saveAs(_ document: FileDocument, to url: URL) async throws(FileStoreError) -> FileDocument {
        let key = DocumentKey(document)
        await acquireLane(for: key)
        defer { releaseLane(for: key) }

        let recoveryEpoch: UUID
        do {
            recoveryEpoch = try await document.recoveryBuffer.mintRecoveryEpoch()
        } catch {
            throw .writeFailed(underlying: error)
        }
        let saved = try await writeSaveAs(document, to: url, recoveryEpoch: recoveryEpoch)
        acceptedLineage.removeValue(forKey: key)
        return saved
    }

    func retire(_ document: FileDocument) async {
        let key = DocumentKey(document)
        await acquireLane(for: key)
        acceptedLineage.removeValue(forKey: key)
        releaseLane(for: key)
    }

    func lineageCount(for document: FileDocument) -> Int {
        acceptedLineage[DocumentKey(document)]?.count ?? 0
    }

    /// Releases the source baseline retained for a completed result. This is
    /// called after the model has reconciled the result with the active
    /// document, not merely when disk IO finishes.
    func acknowledge(_ result: DocumentWriteResult) {
        guard let pending = unacknowledgedResults.removeValue(forKey: result.id) else { return }
        finishRequest(pending.sourceRevision, for: pending.key)
    }

    private func registerPendingSource(_ revision: FileRevision?, for key: DocumentKey) {
        guard let revision else { return }
        let revisionKey = RevisionLineageKey(revision)
        pendingSources[key, default: [:]][revisionKey, default: 0] += 1
    }

    private func finishRequest(_ revision: FileRevision?, for key: DocumentKey) {
        if let revision {
            let revisionKey = RevisionLineageKey(revision)
            let remaining = (pendingSources[key]?[revisionKey] ?? 1) - 1
            if remaining > 0 {
                pendingSources[key]?[revisionKey] = remaining
            } else {
                pendingSources[key]?[revisionKey] = nil
                if pendingSources[key]?.isEmpty == true {
                    pendingSources[key] = nil
                }
            }
        }
        compactLineage(for: key)
    }

    /// Once no queued caller still references an earlier source revision,
    /// retaining its source-to-output mapping merely grows memory. A later
    /// save receives the accepted output directly from the model, so it does
    /// not need historical mappings.
    private func compactLineage(for key: DocumentKey) {
        var retainedKeys: Set<RevisionLineageKey> = []
        if let pending = pendingSources[key] {
            retainedKeys.formUnion(pending.keys)
        }
        for result in unacknowledgedResults.values where result.key == key {
            if let source = result.sourceRevision {
                retainedKeys.insert(RevisionLineageKey(source))
            }
            if let expected = result.expectedRevision {
                retainedKeys.insert(RevisionLineageKey(expected))
            }
        }
        guard !retainedKeys.isEmpty else {
            acceptedLineage[key] = nil
            return
        }
        acceptedLineage[key] = acceptedLineage[key]?.filter { retainedKeys.contains($0.key) }
    }

    private func baseline(for document: FileDocument) -> FileRevision? {
        guard var revision = document.lastKnownRevision else { return nil }
        var visited: Set<RevisionLineageKey> = []
        let lineage = acceptedLineage[DocumentKey(document)] ?? [:]
        while true {
            let key = RevisionLineageKey(revision)
            guard visited.insert(key).inserted, let accepted = lineage[key] else { break }
            revision = accepted
        }
        return revision
    }

    private func record(
        _ document: FileDocument,
        source: FileRevision?,
        expected: FileRevision?
    ) {
        guard let source, let output = document.lastKnownRevision else { return }
        let key = DocumentKey(document)
        acceptedLineage[key, default: [:]][RevisionLineageKey(source)] = output
        if let expected, expected != source {
            acceptedLineage[key, default: [:]][RevisionLineageKey(expected)] = output
        }
    }

    private func acquireLane(for key: DocumentKey) async {
        guard occupiedLanes.contains(key) else {
            occupiedLanes.insert(key)
            return
        }
        await withCheckedContinuation { continuation in
            laneWaiters[key, default: []].append(continuation)
            onRequestQueued?()
        }
    }

    private func releaseLane(for key: DocumentKey) {
        if var waiters = laneWaiters[key], !waiters.isEmpty {
            let next = waiters.removeFirst()
            laneWaiters[key] = waiters.isEmpty ? nil : waiters
            next.resume()
        } else {
            occupiedLanes.remove(key)
        }
    }

    private func write(
        _ document: FileDocument,
        expectedRevision: FileRevision?
    ) async throws(FileStoreError) -> FileDocument {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try document.saving(expectedRevision: expectedRevision)
            }.value
        } catch let error as FileStoreError {
            throw error
        } catch {
            throw .writeFailed(underlying: error)
        }
    }

    private func writeSaveAs(
        _ document: FileDocument,
        to url: URL,
        recoveryEpoch: UUID
    ) async throws(FileStoreError) -> FileDocument {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try document.saveAs(url, recoveryEpoch: recoveryEpoch)
            }.value
        } catch let error as FileStoreError {
            throw error
        } catch {
            throw .writeFailed(underlying: error)
        }
    }
}

struct DocumentWriteResult: Sendable {
    let id: UUID
    let document: FileDocument
    /// Baseline attached to the caller's original document snapshot.
    let sourceRevision: FileRevision?
    /// Baseline used by the conditional write after accepted-save lineage.
    let expectedRevision: FileRevision?
}

private struct PendingWriteResult {
    let key: DocumentKey
    let sourceRevision: FileRevision?
    let expectedRevision: FileRevision?
}

private struct DocumentKey: Hashable {
    let id: String
    let recoveryEpoch: UUID

    init(_ document: FileDocument) {
        id = document.id
        recoveryEpoch = document.recoveryEpoch
    }
}

private struct RevisionLineageKey: Hashable {
    let url: URL
    let modificationDate: Date?
    let fileSize: Int
    let fileObjectID: PhysicalFileIdentity.FileObjectID?
    let sha256: String

    init(_ revision: FileRevision) {
        url = revision.url.standardizedFileURL
        modificationDate = revision.modificationDate
        fileSize = revision.fileSize
        fileObjectID = revision.fileObjectID
        sha256 = revision.sha256
    }
}
