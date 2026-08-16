import Foundation

extension FileStore {
    /// Decodes a byte snapshot into text with its BOM and encoding.
    ///
    /// Detection order: UTF-8 BOM, UTF-16 LE/BE BOM, then strict UTF-8.
    /// Malformed input throws `.decodingFailed` with one diagnostic for the
    /// first invalid byte sequence (zero-based byte offset into `data`); no
    /// replacement characters or text snapshot are ever produced.
    func decode(_ data: Data) throws(FileStoreError) -> FileDecodedPayload {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            // `subdata` (not `dropFirst`): a dropFirst slice keeps its original
            // absolute indices, which traps when re-indexed as a `Data`.
            let payload = data.subdata(in: 3 ..< data.count)
            if let offset = utf8InvalidByteOffset(in: payload) {
                throw .decodingFailed([
                    FileDecodingDiagnostic(message: "Invalid UTF-8 byte sequence.", byteOffset: offset + 3),
                ])
            }
            // The payload was just validated as strict UTF-8, so this decode
            // is guaranteed to succeed.
            // swiftlint:disable:next optional_data_string_conversion
            return FileDecodedPayload(text: String(decoding: payload, as: UTF8.self), encoding: .utf8, bom: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return try decodeUTF16(
                data.subdata(in: 2 ..< data.count),
                encoding: .utf16LittleEndian,
                bom: .utf16LittleEndian
            )
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return try decodeUTF16(
                data.subdata(in: 2 ..< data.count),
                encoding: .utf16BigEndian,
                bom: .utf16BigEndian
            )
        }
        if let offset = utf8InvalidByteOffset(in: data) {
            throw .decodingFailed([
                FileDecodingDiagnostic(message: "Invalid UTF-8 byte sequence.", byteOffset: offset),
            ])
        }
        // Same validation guarantee as the BOM path above.
        // swiftlint:disable:next optional_data_string_conversion
        return FileDecodedPayload(text: String(decoding: data, as: UTF8.self), encoding: .utf8, bom: .none)
    }

    private func decodeUTF16(
        _ data: Data,
        encoding: String.Encoding,
        bom: FileBOM
    ) throws(FileStoreError) -> FileDecodedPayload {
        guard let text = String(data: data, encoding: encoding) else {
            let unitOffset = utf16InvalidUnitOffset(in: data, littleEndian: encoding == .utf16LittleEndian)
            throw .decodingFailed([
                FileDecodingDiagnostic(
                    message: "Invalid UTF-16 byte sequence.",
                    byteOffset: unitOffset + 2 // + the BOM bytes
                ),
            ])
        }
        return FileDecodedPayload(text: text, encoding: encoding, bom: bom)
    }

    // Returns the byte offset of the first invalid UTF-8 sequence, or `nil`
    // when the payload is well-formed. Overlong encodings, surrogate code
    // points, and values above U+10FFFF are all invalid.
    //
    // The validation is deliberately one linear pass over the payload: each
    // branch checks one UTF-8 rule (lead byte, continuation bytes, overlong
    // form, surrogate range, maximum code point). Splitting the pass would
    // obscure the byte arithmetic, so the complexity budget is documented
    // rather than worked around.
    // swiftlint:disable:next cyclomatic_complexity
    private func utf8InvalidByteOffset(in data: Data) -> Int? {
        var index = 0
        while index < data.count {
            let byte = data[index]
            if byte < 0x80 {
                index += 1
                continue
            }
            let length: Int
            var codePoint: UInt32
            switch byte {
            case 0xC2 ... 0xDF:
                length = 2
                codePoint = UInt32(byte & 0x1F)
            case 0xE0 ... 0xEF:
                length = 3
                codePoint = UInt32(byte & 0x0F)
            case 0xF0 ... 0xF4:
                length = 4
                codePoint = UInt32(byte & 0x07)
            default:
                // Stray continuation byte or invalid lead byte.
                return index
            }
            guard index + length <= data.count else { return index }
            for continuation in 1 ..< length {
                let next = data[index + continuation]
                guard next & 0xC0 == 0x80 else { return index }
                codePoint = (codePoint << 6) | UInt32(next & 0x3F)
            }
            let minimumCodePoint: UInt32 = switch length {
            case 2: 0x80
            case 3: 0x800
            default: 0x10000
            }
            if codePoint < minimumCodePoint {
                return index
            }
            if length == 3, (0xD800 ... 0xDFFF).contains(codePoint) {
                return index
            }
            if length == 4, codePoint > 0x10FFFF {
                return index
            }
            index += length
        }
        return nil
    }

    /// Returns the byte offset (into `data`) of the first invalid UTF-16
    /// sequence: an unpaired surrogate or a truncated/odd trailing unit.
    private func utf16InvalidUnitOffset(in data: Data, littleEndian: Bool) -> Int {
        func unit(at offset: Int) -> UInt16 {
            if littleEndian {
                return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            }
            return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        }
        var index = 0
        while index + 1 < data.count {
            let value = unit(at: index)
            if (0xD800 ... 0xDBFF).contains(value) {
                guard index + 3 < data.count else { return index }
                let next = unit(at: index + 2)
                guard (0xDC00 ... 0xDFFF).contains(next) else { return index }
                index += 4
            } else if (0xDC00 ... 0xDFFF).contains(value) {
                return index
            } else {
                index += 2
            }
        }
        return index
    }
}
