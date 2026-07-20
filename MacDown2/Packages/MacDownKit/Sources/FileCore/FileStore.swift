import Foundation

/// Errors that can occur during file storage operations.
public enum FileStoreError: Error {
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)
    case encodingDetectionFailed
    case invalidURL
}

/// Reads and writes file content with encoding detection and atomic saves.
///
/// All IO is performed on the calling context; callers that need async behavior
/// should wrap calls in an actor or Task (e.g. `FileDocument`'s autosave actor).
public struct FileStore: Sendable {
    /// The default encoding used when no BOM or explicit signal is present.
    public static let defaultEncoding: String.Encoding = .utf8

    public init() {}

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
        guard url.isFileURL else {
            throw .invalidURL
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .readFailed(underlying: error)
        }

        // Try explicit BOM encodings first.
        let bomEncodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
        for encoding in bomEncodings {
            if let content = String(data: data, encoding: encoding) {
                return (content, encoding)
            }
        }

        throw .encodingDetectionFailed
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
    public func write(
        _ content: String,
        to url: URL,
        encoding: String.Encoding = FileStore.defaultEncoding
    ) throws(FileStoreError) {
        guard url.isFileURL else {
            throw .invalidURL
        }

        guard let data = content.data(using: encoding, allowLossyConversion: false) else {
            throw .encodingDetectionFailed
        }

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            // Best-effort cleanup of the temp file; do not let cleanup failures mask the real error.
            try? FileManager.default.removeItem(at: temporaryURL)
            throw .writeFailed(underlying: error)
        }
    }
}
