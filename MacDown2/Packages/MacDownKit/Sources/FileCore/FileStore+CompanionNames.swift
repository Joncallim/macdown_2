import Darwin
import Foundation

extension FileStore {
    /// `.<name>.<infix>-<uuid>` for a staged or preserved sibling of `url`. A file
    /// system caps a component at 255 bytes, so a long name is truncated (on a
    /// character boundary) — the old form made any file named ~212 bytes or more
    /// impossible to save (`File name too long`).
    static func companionName(for url: URL, infix: String) -> String {
        let name = url.lastPathComponent
        var kept = ""
        var bytes = 0
        for character in name {
            let size = String(character).utf8.count
            if bytes + size > maximumCompanionNameBytes {
                break
            }
            kept.append(character)
            bytes += size
        }
        return ".\(kept).\(infix)-\(UUID().uuidString)"
    }

    /// Leaves room for the dot, the infix and a 36-character UUID within 255 bytes.
    static let maximumCompanionNameBytes = 120

    /// Replacing a file the user cannot write must fail, not quietly succeed
    /// because they can write the DIRECTORY (the replace is a rename).
    func requireWritableIfExisting(_ url: URL) throws(FileStoreError) {
        if FileManager.default.fileExists(atPath: url.path), access(url.path, W_OK) != 0 {
            throw .permissionDenied
        }
    }
}
