import CryptoKit
import Foundation

/// Errors that can occur during file storage operations.
public enum FileStoreError: Error {
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)
    case encodingDetectionFailed
    case invalidURL
    case fileChangedDuringRead
    case notRegularFile
    case fileMissing
    case permissionDenied
    /// The bytes could not be decoded with the detected encoding. One
    /// diagnostic describes the first invalid byte sequence; no replacement
    /// characters or text snapshot are produced.
    case decodingFailed([FileDecodingDiagnostic])
    /// Conditional publication could not restore a displaced external writer.
    /// The external bytes were preserved at the returned sibling URL.
    case conditionalPublicationRecoveryRequired(URL)
}

/// Reads and writes file content with encoding detection and atomic saves.
///
/// All IO is performed on the calling context; callers that need async behavior
/// should wrap calls in an actor or Task (e.g. `FileDocument`'s autosave actor).
public struct FileStore: Sendable {
    /// The default encoding used when no BOM or explicit signal is present.
    public static let defaultEncoding: String.Encoding = .utf8

    /// Test-only seam used to model a writer that wins immediately after our
    /// atomic replacement. Production callers use the public empty initializer.
    private let afterReplacement: (@Sendable (URL) throws -> Void)?
    private let beforePublication: (@Sendable (URL) throws -> Void)?
    private let afterBaselineVerification: (@Sendable (URL) throws -> Void)?
    private let conditionalPublicationHooks: ConditionalPublicationTestHooks?

    public init() {
        afterReplacement = nil
        beforePublication = nil
        afterBaselineVerification = nil
        conditionalPublicationHooks = nil
    }

    init(afterReplacement: @escaping @Sendable (URL) throws -> Void) {
        self.afterReplacement = afterReplacement
        beforePublication = nil
        afterBaselineVerification = nil
        conditionalPublicationHooks = nil
    }

    init(beforePublication: @escaping @Sendable (URL) throws -> Void) {
        afterReplacement = nil
        self.beforePublication = beforePublication
        afterBaselineVerification = nil
        conditionalPublicationHooks = nil
    }

    init(afterBaselineVerification: @escaping @Sendable (URL) throws -> Void) {
        afterReplacement = nil
        beforePublication = nil
        self.afterBaselineVerification = afterBaselineVerification
        conditionalPublicationHooks = nil
    }

    init(conditionalPublicationHooks: ConditionalPublicationTestHooks) {
        afterReplacement = nil
        beforePublication = nil
        afterBaselineVerification = nil
        self.conditionalPublicationHooks = conditionalPublicationHooks
    }

    init(
        afterBaselineVerification: @escaping @Sendable (URL) throws -> Void,
        conditionalPublicationHooks: ConditionalPublicationTestHooks
    ) {
        afterReplacement = nil
        beforePublication = nil
        self.afterBaselineVerification = afterBaselineVerification
        self.conditionalPublicationHooks = conditionalPublicationHooks
    }

    /// Reads the contents of a file at `url`.
    ///
    /// Encoding detection order:
    /// 1. UTF-8 BOM
    /// 2. UTF-16 BOM (LE/BE)
    /// 3. UTF-8 (default)
    ///
    /// - Parameters:
    ///   - url: File URL to read from. Must be a security-scoped-ready file reference.
    /// - Returns: The file content and the encoding used to decode it.
    public func read(from url: URL) throws(FileStoreError) -> (content: String, encoding: String.Encoding) {
        let snapshot = try readSnapshot(from: url)
        return (snapshot.text, snapshot.encoding)
    }

    public func readSnapshot(from url: URL) throws(FileStoreError) -> FileSnapshot {
        guard url.isFileURL else { throw .invalidURL }

        for attempt in 0 ..< 2 {
            let before = try metadata(at: url)
            guard before.isRegularFile else { throw .notRegularFile }

            let data: Data
            do {
                // A mapped region can reflect subsequent mutations while it is
                // being hashed/decoded. Snapshot reads need owned immutable
                // bytes, with the metadata checks bracketing that copy.
                data = try Data(contentsOf: url)
            } catch {
                throw mapReadError(error)
            }

            let after = try metadata(at: url)
            let stable = metadataIsStable(before, after) && after.fileSize == data.count
            guard stable else {
                if attempt == 0 {
                    continue
                }
                throw .fileChangedDuringRead
            }

            let payload = try decode(data)
            return FileSnapshot(
                text: payload.text,
                encoding: payload.encoding,
                bom: payload.bom,
                revision: FileRevision(
                    url: url.standardizedFileURL,
                    modificationDate: after.modificationDate,
                    fileSize: data.count,
                    fileObjectID: after.fileObjectID,
                    sha256: sha256(data)
                )
            )
        }
        throw .fileChangedDuringRead
    }

    /// Writes `content` to `url` atomically.
    ///
    /// The implementation writes to a sibling temporary file and then replaces
    /// the destination with it, so a crash or interruption never leaves a
    /// partially-written file.
    ///
    /// - Parameters:
    ///   - content: Text to write.
    ///   - url: Destination file URL.
    ///   - encoding: Encoding to use for the write. Defaults to UTF-8.
    ///   - bom: Byte-order-mark policy for the write. When non-`.none` the
    ///     matching byte prefix is emitted before the encoded text so a
    ///     subsequent snapshot read reproduces the exact metadata.
    @discardableResult
    public func write(
        _ content: String,
        to url: URL,
        encoding: String.Encoding = FileStore.defaultEncoding,
        bom: FileBOM = .none,
        expectedRevision: FileRevision? = nil
    ) throws(FileStoreError) -> FileRevision {
        guard url.isFileURL else { throw .invalidURL }

        guard let data = encodedData(content, encoding: encoding, bom: bom) else {
            throw .encodingDetectionFailed
        }

        do {
            return try FilePublicationLocks.shared.withLock(for: url.standardizedFileURL) {
                try writeLocked(content, to: url, data: data, expectedRevision: expectedRevision)
            }
        } catch {
            throw mapWriteError(error)
        }
    }

    /// Encodes `content` for disk, emitting the requested BOM byte prefix.
    /// Returns `nil` when the encoding cannot represent the text losslessly.
    private func encodedData(_ content: String, encoding: String.Encoding, bom: FileBOM) -> Data? {
        guard let body = content.data(using: encoding, allowLossyConversion: false) else { return nil }
        switch bom {
        case .none:
            return body
        case .utf8:
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(body)
            return data
        case .utf16LittleEndian:
            var data = Data([0xFF, 0xFE])
            data.append(body)
            return data
        case .utf16BigEndian:
            var data = Data([0xFE, 0xFF])
            data.append(body)
            return data
        }
    }

    private func writeLocked(
        _ content: String,
        to url: URL,
        data: Data,
        expectedRevision: FileRevision?
    ) throws(FileStoreError) -> FileRevision {
        if let expectedRevision {
            let actual = try readSnapshot(from: url).revision
            guard actual == expectedRevision else { throw .fileChangedDuringRead }
        }

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            try beforePublication?(url)
            // Re-check immediately before publishing the replacement. A
            // conditional publication then uses `RENAME_SWAP`: the previous
            // destination is atomically moved to `temporaryURL`, where its
            // identity and bytes are verified before accepting our write. A
            // non-cooperating writer that wins after this check is therefore
            // restored instead of being overwritten.
            if let expectedRevision {
                let actual = try readSnapshot(from: url).revision
                guard actual == expectedRevision else { throw FileStoreError.fileChangedDuringRead }
            }
            // Test seam deliberately positioned in the former verification to
            // replacement window. The conditional swap below must preserve a
            // direct, non-cooperating write issued here.
            try afterBaselineVerification?(url)
            if let expectedRevision {
                try conditionallyPublish(
                    temporaryURL: temporaryURL,
                    destinationURL: url,
                    expectedRevision: expectedRevision,
                    hooks: conditionalPublicationHooks
                )
            } else if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
            try afterReplacement?(url)
        } catch {
            let mapped = mapWriteError(error)
            // A failed rollback has moved the displaced external version to a
            // sibling recovery URL (or left it at `temporaryURL`). Never
            // delete that evidence while surfacing the recovery location.
            if case .conditionalPublicationRecoveryRequired = mapped {
                throw mapped
            }
            // Best-effort cleanup of our own temporary file; do not let
            // cleanup failures mask the real error.
            try? FileManager.default.removeItem(at: temporaryURL)
            throw mapped
        }

        let snapshot = try readSnapshot(from: url)
        guard snapshot.text == content,
              snapshot.revision.fileSize == data.count,
              snapshot.revision.sha256 == sha256(data)
        else {
            // A concurrent writer replaced our destination before we could
            // establish its baseline. Do not return that foreign revision as a
            // successful save: callers must remain dirty and reconcile it.
            throw .fileChangedDuringRead
        }
        return snapshot.revision
    }

    private func metadata(at url: URL) throws(FileStoreError) -> FileMetadata {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw mapReadError(error)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw .notRegularFile }
        let volume = attributes[.systemNumber] as? NSNumber
        let file = attributes[.systemFileNumber] as? NSNumber
        let objectID: PhysicalFileIdentity.FileObjectID? = if let volume, let file {
            .init(volume: volume.stringValue, file: file.stringValue)
        } else {
            nil
        }
        return FileMetadata(
            modificationDate: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            fileObjectID: objectID,
            isRegularFile: true
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func metadataIsStable(_ before: FileMetadata, _ after: FileMetadata) -> Bool {
        let identityMatches: Bool = if let beforeID = before.fileObjectID, let afterID = after.fileObjectID {
            beforeID == afterID
        } else {
            true
        }
        return identityMatches
            && before.fileSize == after.fileSize
            && before.modificationDate == after.modificationDate
            && before.isRegularFile == after.isRegularFile
    }

    static var publicationLockCountForTesting: Int {
        FilePublicationLocks.shared.count
    }
}

final class FilePublicationLocks: @unchecked Sendable {
    static let shared = FilePublicationLocks()

    private let registryLock = NSLock()
    private var locks: [String: Entry] = [:]

    private struct Entry {
        let lock: NSLock
        var retainCount: Int
    }

    var count: Int {
        registryLock.lock()
        defer { registryLock.unlock() }
        return locks.count
    }

    var isEmpty: Bool {
        registryLock.lock()
        defer { registryLock.unlock() }
        return locks.isEmpty
    }

    func withLock<Result>(for url: URL, _ body: () throws -> Result) rethrows -> Result {
        let key = url.standardizedFileURL.path
        registryLock.lock()
        var entry = locks[key] ?? Entry(lock: NSLock(), retainCount: 0)
        entry.retainCount += 1
        locks[key] = entry
        registryLock.unlock()
        entry.lock.lock()
        defer {
            entry.lock.unlock()
            release(key: key)
        }
        return try body()
    }

    private func release(key: String) {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard var entry = locks[key] else { return }
        entry.retainCount -= 1
        if entry.retainCount == 0 {
            locks[key] = nil
        } else {
            locks[key] = entry
        }
    }
}
