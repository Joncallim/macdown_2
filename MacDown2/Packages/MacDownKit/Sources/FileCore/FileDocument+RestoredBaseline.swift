import Foundation

public extension FileDocument {
    /// The hash to persist as this document's session baseline.
    var baselineSHA256: String? {
        lastKnownRevision?.sha256 ?? restoredBaseSHA256
    }

    func restoringBaseline(sha256: String?) -> FileDocument {
        var copy = self
        copy.restoredBaseSHA256 = sha256
        return copy
    }
}
