import Foundation

public struct FileRevision: Sendable, Equatable {
    public let url: URL
    public let modificationDate: Date?
    public let fileSize: Int
    public let fileObjectID: PhysicalFileIdentity.FileObjectID?
    public let sha256: String

    public init(
        url: URL,
        modificationDate: Date?,
        fileSize: Int,
        fileObjectID: PhysicalFileIdentity.FileObjectID?,
        sha256: String
    ) {
        self.url = url
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.fileObjectID = fileObjectID
        self.sha256 = sha256
    }
}

public struct FileSnapshot: Sendable, Equatable {
    public let text: String
    public let encodingRawValue: UInt
    public let bom: FileBOM
    public let revision: FileRevision

    public var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    /// The decoding metadata carried by this snapshot.
    public var encodingMetadata: FileEncodingMetadata {
        FileEncodingMetadata(encodingRawValue: encodingRawValue, bom: bom)
    }

    public init(text: String, encoding: String.Encoding, bom: FileBOM, revision: FileRevision) {
        self.text = text
        encodingRawValue = encoding.rawValue
        self.bom = bom
        self.revision = revision
    }

    /// Compatibility projection for callers that predate the BOM contract.
    /// Decodes without BOM knowledge; prefer `encodingMetadata` for round
    /// trips that must preserve the byte prefix.
    public init(text: String, encoding: String.Encoding, revision: FileRevision) {
        self.init(text: text, encoding: encoding, bom: .none, revision: revision)
    }
}

struct FileMetadata: Sendable, Equatable {
    let modificationDate: Date?
    let fileSize: Int
    let fileObjectID: PhysicalFileIdentity.FileObjectID?
    let isRegularFile: Bool
}
