import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Content-addressed identity of one exported resource.
///
/// Identity is `(full SHA-256 of the bytes, canonical MIME type)`. Companion
/// filenames are exactly `<64 lowercase hex>.<canonical extension>` so two
/// resources with identical bytes always share a filename and two different
/// resources never collide.
public struct ExportResourceIdentity: Sendable, Equatable, Hashable {
    /// 64 lowercase hexadecimal characters.
    public let sha256: String
    /// Canonical MIME type, e.g. `image/png`.
    public let mimeType: String

    public init(sha256: String, mimeType: String) {
        self.sha256 = sha256
        self.mimeType = mimeType
    }

    /// Computes the identity for a byte payload. `mimeType` is canonicalised by
    /// the caller from the system `UTType` mapping.
    public init(bytes: Data, mimeType: String) {
        sha256 = Self.sha256Hex(of: bytes)
        self.mimeType = mimeType
    }

    /// `<64hex>.<extension>` — the companion filename under the document's assets directory.
    public var fileName: String {
        "\(sha256).\(canonicalExtension)"
    }

    /// The filename extension derived from the canonical MIME type via the
    /// system `UTType` mapping, or `bin` when no mapping exists.
    public var canonicalExtension: String {
        if let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext
        }
        return "bin"
    }

    private static let hexDigits = Array("0123456789abcdef")

    static func sha256Hex(of data: Data) -> String {
        var characters = [Character]()
        characters.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            characters.append(hexDigits[Int(byte >> 4)])
            characters.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(characters)
    }
}

/// One resolved resource: its identity plus the byte payload to package.
public struct ExportResource: Sendable, Equatable {
    public let identity: ExportResourceIdentity
    public let bytes: Data

    public init(identity: ExportResourceIdentity, bytes: Data) {
        self.identity = identity
        self.bytes = bytes
    }
}

/// Maps a filename extension or MIME type to a canonical MIME type using the
/// system `UTType` mapping, with an application/octet-stream fallback.
public enum ExportMIMEType {
    public static func mimeType(forFileExtension ext: String) -> String {
        let trimmed = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty,
              let type = UTType(filenameExtension: trimmed),
              let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }
}
