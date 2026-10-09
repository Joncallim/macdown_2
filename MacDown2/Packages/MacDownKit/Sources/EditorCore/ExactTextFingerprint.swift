import Foundation

/// Identity of a text's EXACT UTF-16 content (length plus an FNV-1a hash over the units).
///
/// Swift `String` equality — and so `onChange(of: text)` and `hashValue` — is canonical: U+00C5 and U+212B compare
/// equal although the text system treats them as different text. Find results bound to a canonical comparison
/// survived such a same-length change and could be applied to text that no longer matched the literal query.
public struct ExactTextFingerprint: Hashable, Sendable {
    public let utf16Length: Int
    private let hash: UInt64

    public init(_ text: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var count = 0
        for unit in text.utf16 {
            hash = (hash ^ UInt64(unit)) &* 0x0000_0100_0000_01B3
            count += 1
        }
        utf16Length = count
        self.hash = hash
    }
}
