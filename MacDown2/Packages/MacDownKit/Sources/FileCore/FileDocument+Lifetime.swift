import Foundation

public extension FileDocument {
    /// Constructs a document with a recovery epoch that has first observed
    /// the buffer's durable ownership ledger. Use this at asynchronous app
    /// boundaries for new tabs, files, and replacement lifetimes.
    static func create(
        fileURL: URL? = nil,
        text: String = "",
        encoding: FileEncodingMetadata = .utf8Default,
        format: FileFormat? = nil,
        fileStore: FileStore = FileStore(),
        recoveryBuffer: RecoveryBuffer = .shared,
        documentID: String? = nil,
        recoveryEpoch: UUID? = nil
    ) async throws -> FileDocument {
        let epoch: UUID = if let recoveryEpoch {
            recoveryEpoch
        } else {
            try await recoveryBuffer.mintRecoveryEpoch()
        }
        return FileDocument(
            fileURL: fileURL,
            text: text,
            format: format,
            encoding: encoding,
            fileStore: fileStore,
            recoveryBuffer: recoveryBuffer,
            documentID: documentID,
            recoveryEpoch: epoch
        )
    }

    /// Asynchronous counterpart for identity changes that need a managed
    /// lifetime. The buffer observes its durable high-water before minting.
    func withFreshRecoveryLifetime(preparedBy buffer: RecoveryBuffer) async throws -> FileDocument {
        try await withReplacementRecoveryLifetime(buffer.mintRecoveryEpoch())
    }

    /// Re-points an existing file-backed document with a recovery epoch that
    /// has observed the durable ownership ledger first.
    func renamed(to url: URL, preparedBy buffer: RecoveryBuffer) async throws -> FileDocument {
        let epoch = try await buffer.mintRecoveryEpoch()
        return renamed(to: url, recoveryEpoch: epoch)
    }
}
