import Foundation

extension RecoveryBuffer {
    /// Reads a recovery artifact as exactly the UTF-8 text that was written.
    ///
    /// `String(contentsOf:encoding: .utf8)` (and `String(data:encoding:)`)
    /// strip a leading `EF BB BF` as if it were a byte-order mark, which would
    /// silently delete a U+FEFF the user actually authored (#183 F11). Recovery
    /// files never carry a transport BOM — the writer encodes with
    /// `String.utf8` — so the bytes are decoded verbatim and rejected if they
    /// are not valid UTF-8.
    static func readExactUTF8(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSURLErrorKey: url])
        }
        return text
    }
}
