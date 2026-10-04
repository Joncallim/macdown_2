import Foundation

extension FileStore {
    /// Encodes `content` for disk, emitting the requested BOM byte prefix.
    /// Returns `nil` unless the encoding represents the text losslessly: a
    /// converter that silently normalises (composing a decomposed sequence,
    /// say) is refused rather than trusted, since the reopened text would no
    /// longer be what the user wrote.
    func encodedData(_ content: String, encoding: String.Encoding, bom: FileBOM) -> Data? {
        guard let body = content.data(using: encoding, allowLossyConversion: false) else { return nil }
        // A leading U+FEFF written without a BOM is byte-identical to a BOM
        // and would be consumed as one on reopen, dropping the scalar.
        if bom == .none, Self.bomCapableEncodings.contains(encoding), content.unicodeScalars.first == "\u{FEFF}" {
            return nil
        }
        // Mirror case: a leading U+FFFE is the other byte order's BOM (`FE FF` LE, `FF FE` BE) and is rejected on read.
        if bom == .none, [.utf16LittleEndian, .utf16BigEndian].contains(encoding),
           content.unicodeScalars.first == "\u{FFFE}" {
            return nil
        }
        if !Self.unicodeEncodings.contains(encoding) {
            guard let roundTripped = String(data: body, encoding: encoding),
                  roundTripped.unicodeScalars.elementsEqual(content.unicodeScalars)
            else { return nil }
        }
        let prefix: [UInt8] = switch bom {
        case .none: []
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        }
        return prefix.isEmpty ? body : Data(prefix) + body
    }

    static let bomCapableEncodings: Set<String.Encoding> = [
        .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
    ]

    static let unicodeEncodings: Set<String.Encoding> = [
        .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian,
    ]
}
