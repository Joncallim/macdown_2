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
    public let revision: FileRevision

    public var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    public init(text: String, encoding: String.Encoding, revision: FileRevision) {
        self.text = text
        encodingRawValue = encoding.rawValue
        self.revision = revision
    }
}

struct FileMetadata: Sendable, Equatable {
    let modificationDate: Date?
    let fileSize: Int
    let fileObjectID: PhysicalFileIdentity.FileObjectID?
    let isRegularFile: Bool
}
