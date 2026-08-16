import Foundation

/// The byte-order-mark policy of a file's decoded text.
///
/// Captured with the immutable byte snapshot so writes can reproduce the
/// exact on-disk byte prefix, and so session restore can re-interpret text
/// without re-reading the file.
public enum FileBOM: String, Sendable, Equatable, Codable {
    case none
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}

/// The decoding metadata carried with a document's text.
///
/// `encodingRawValue` is the `String.Encoding.rawValue` used to decode the
/// bytes; `bom` records the byte-order mark that was present (or absent).
public struct FileEncodingMetadata: Sendable, Equatable, Codable {
    public let encodingRawValue: UInt
    public let bom: FileBOM

    public init(encodingRawValue: UInt, bom: FileBOM) {
        self.encodingRawValue = encodingRawValue
        self.bom = bom
    }

    public init(encoding: String.Encoding, bom: FileBOM) {
        self.init(encodingRawValue: encoding.rawValue, bom: bom)
    }

    /// Decodes session JSON. Unknown or mutually inconsistent
    /// `encodingRawValue`/`bom` pairs (a corrupted or hand-edited session) are
    /// replaced with the documented default (UTF-8, no BOM) instead of
    /// carrying garbage metadata into restore, where it would only surface
    /// later as a failed save — or, for a mismatched pair, as bytes written
    /// under the wrong prefix.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(UInt.self, forKey: .encodingRawValue)
        let bom = try container.decode(FileBOM.self, forKey: .bom)
        if Self.consistentEncoding(for: rawValue, bom: bom) != nil {
            self.init(encodingRawValue: rawValue, bom: bom)
        } else {
            self = .utf8Default
        }
    }

    /// The encoding a BOM kind may pair with; `nil` for inconsistent pairs.
    /// The decode paths produce exactly these pairs (UTF-8 for the UTF-8
    /// BOM, the matching endianness for each UTF-16 BOM).
    private static func consistentEncoding(for rawValue: UInt, bom: FileBOM) -> String.Encoding? {
        switch bom {
        case .none:
            let encoding = String.Encoding(rawValue: rawValue)
            return supportedEncodingRawValues.contains(rawValue) ? encoding : nil
        case .utf8:
            return rawValue == String.Encoding.utf8.rawValue ? .utf8 : nil
        case .utf16LittleEndian:
            return rawValue == String.Encoding.utf16LittleEndian.rawValue ? .utf16LittleEndian : nil
        case .utf16BigEndian:
            return rawValue == String.Encoding.utf16BigEndian.rawValue ? .utf16BigEndian : nil
        }
    }

    /// The encodings the app can read and write; everything else in a
    /// persisted session is malformed.
    private static let supportedEncodingRawValues: Set<UInt> = [
        String.Encoding.utf8.rawValue,
        String.Encoding.utf16.rawValue,
        String.Encoding.utf16LittleEndian.rawValue,
        String.Encoding.utf16BigEndian.rawValue,
    ]

    /// The encoding used to decode the text.
    public var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    /// The documented default for new documents and legacy/malformed session
    /// metadata: UTF-8 without a BOM.
    public static let utf8Default = FileEncodingMetadata(encoding: .utf8, bom: .none)
}

/// One decoding problem found in a file's raw bytes.
public struct FileDecodingDiagnostic: Sendable, Equatable {
    public let message: String
    /// Zero-based byte offset into the copied input bytes where the invalid
    /// sequence begins.
    public let byteOffset: Int

    public init(message: String, byteOffset: Int) {
        self.message = message
        self.byteOffset = byteOffset
    }
}

/// The result of decoding a byte snapshot: the text, the BOM it carried, and
/// the encoding that decoded it. A failed decode yields no text.
struct FileDecodedPayload: Sendable, Equatable {
    let text: String
    let encoding: String.Encoding
    let bom: FileBOM
}
