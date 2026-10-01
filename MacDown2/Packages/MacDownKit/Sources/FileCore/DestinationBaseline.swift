import Darwin
import Foundation

/// What a Save As destination looked like when the user authorised it (#183
/// F22). Publishing against this baseline means a file another process created,
/// replaced or modified in the meantime is never silently overwritten — the same
/// external-writer protection an ordinary Save has.
public enum DestinationBaseline: Sendable, Equatable {
    /// No file existed at the destination.
    case absent
    /// The destination existed with exactly this content/identity.
    case revision(FileRevision)
}

public extension FileStore {
    /// The destination's current baseline: `.absent` for a missing path, the
    /// file's revision for a regular file. Anything else (a directory, an
    /// unreadable file) throws, so Save As is refused rather than guessed at.
    func destinationBaseline(at url: URL) throws(FileStoreError) -> DestinationBaseline {
        do {
            return try .revision(readRevision(from: url))
        } catch .fileMissing {
            return .absent
        }
    }
}

public extension FileDocument {
    /// The baseline Save As to `url` must publish against. Save As onto the
    /// document's own file keeps ordinary Save's protection (what the document
    /// last knew); any other destination is captured fresh.
    func saveAsBaseline(for url: URL) throws(FileStoreError) -> DestinationBaseline? {
        if url.standardizedFileURL == fileURL?.standardizedFileURL {
            return lastKnownRevision.map { .revision($0) }
        }
        return try fileStore.destinationBaseline(at: url)
    }
}

extension FileStore {
    /// Publishes `temporaryURL` at `destinationURL` only if nothing exists
    /// there (`RENAME_EXCL`); an existing file means the baseline was stale.
    func publishExclusively(_ temporaryURL: URL, to destinationURL: URL) throws(FileStoreError) {
        let result = temporaryURL.path.withCString { source in
            destinationURL.path.withCString { target in
                renamex_np(source, target, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST {
                throw .fileChangedDuringRead
            }
            throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))
        }
    }

    /// Folds the two ways a caller can express a destination expectation into
    /// one revision to match and whether the destination must not exist.
    static func resolveBaseline(
        _ expectedRevision: FileRevision?,
        _ baseline: DestinationBaseline?
    ) -> (FileRevision?, Bool) {
        precondition(expectedRevision == nil || baseline == nil, "pass one baseline, not both")
        switch baseline {
        case let .revision(revision): return (revision, false)
        case .absent: return (nil, true)
        case nil: return (expectedRevision, false)
        }
    }

    func requireAbsentIfNeeded(_ requireAbsent: Bool, at url: URL) throws(FileStoreError) {
        if requireAbsent, FileManager.default.fileExists(atPath: url.path) {
            throw .fileChangedDuringRead
        }
    }

    /// Publishes the staged file: conditionally against `expectedRevision`,
    /// exclusively when the destination must not exist, else by replacement.
    func publishStaged(
        _ temporaryURL: URL,
        to url: URL,
        expectedRevision: FileRevision?,
        requireAbsent: Bool
    ) throws(FileStoreError) {
        do {
            if let expectedRevision {
                try conditionallyPublish(
                    temporaryURL: temporaryURL,
                    destinationURL: url,
                    expectedRevision: expectedRevision,
                    hooks: conditionalPublicationHooks
                )
            } else if requireAbsent {
                try publishExclusively(temporaryURL, to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch let error as FileStoreError {
            throw error
        } catch {
            throw mapWriteError(error)
        }
    }
}
