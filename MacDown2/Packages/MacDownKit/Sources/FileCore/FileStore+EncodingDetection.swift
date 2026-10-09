import Foundation

public extension FileStoreError {
    /// The bytes could not be decoded as text under the policy used (as opposed to
    /// the file being missing, unreadable or changing underneath the read).
    var isUndecodableText: Bool {
        switch self {
        case .decodingFailed, .encodingDetectionFailed: true
        default: false
        }
    }
}

public extension FileStore {
    /// Conservative detection for a file whose bytes are neither BOM-marked nor
    /// valid UTF-8 (those are handled first, by the automatic decode). It names
    /// an encoding only when the bytes themselves give strong, checkable
    /// evidence — never a statistical guess:
    ///
    /// - BOM-less UTF-16: ASCII-range text has a zero byte in (nearly) every
    ///   code unit, always on the same side, and the text decodes strictly and
    ///   re-encodes to exactly the bytes read.
    ///
    /// Everything else (Latin-1, Windows-1252, Shift-JIS, …) is ambiguous by
    /// nature — the same bytes are valid text in many of them — so it returns
    /// `nil` and the caller must offer an explicit "Open With Encoding…" choice.
    /// Undecodable bytes are never replaced.
    static func conservativelyDetectedEncoding(of data: Data) -> FileEncodingMetadata? {
        guard data.count >= 2, data.count.isMultiple(of: 2) else { return nil }
        var zerosAtEven = 0
        var zerosAtOdd = 0
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == 0 {
                zerosAtEven += 1
            }
            if data[index + 1] == 0 {
                zerosAtOdd += 1
            }
            index += 2
        }
        let units = data.count / 2
        let candidate: String.Encoding
        // Little-endian ASCII text is `char 00`: zeros at odd offsets only.
        if zerosAtEven == 0, zerosAtOdd * 100 >= units * 80 {
            candidate = .utf16LittleEndian
        } else if zerosAtOdd == 0, zerosAtEven * 100 >= units * 80 {
            candidate = .utf16BigEndian
        } else {
            return nil
        }
        guard let text = String(data: data, encoding: candidate),
              !text.unicodeScalars.contains("\u{0}"),
              text.data(using: candidate, allowLossyConversion: false) == data
        else { return nil }
        return FileEncodingMetadata(encoding: candidate, bom: .none)
    }

    /// Reads `url` and applies `conservativelyDetectedEncoding(of:)`.
    func conservativelyDetectedEncoding(at url: URL) -> FileEncodingMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.conservativelyDetectedEncoding(of: data)
    }
}
