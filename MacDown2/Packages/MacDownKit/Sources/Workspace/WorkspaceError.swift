import FileCore
import Foundation

/// Errors surfaced by the workspace shell when routing commands to `FileCore`.
public enum WorkspaceError: Error {
    case openFailed(underlying: FileStoreError)
    case saveFailed(underlying: FileStoreError)
    /// A competing external writer was preserved separately after a failed
    /// conditional publication. The current document remains dirty.
    case conditionalPublicationRecoveryRequired(URL)
    /// The document was saved, but its prior crash-recovery record could not
    /// be safely migrated or removed. Keep the window open and retry cleanup,
    /// or use Save As after revealing the retained recovery copy.
    case recoveryCleanupRequired(URL)
    case noActiveDocument
    case unresolvedExternalConflict
    case backingFileUnavailable(FileBackingIssue)
}

extension WorkspaceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .openFailed:
            String(localized: "The document could not be opened.")
        case .saveFailed:
            String(localized: "The document could not be saved.")
        case let .conditionalPublicationRecoveryRequired(url):
            String(
                localized: """
                MacDown preserved a competing version as \(url.lastPathComponent). \
                Reveal it, then use Save As to keep this copy.
                """
            )
        case let .recoveryCleanupRequired(url):
            String(
                localized: """
                MacDown retained recovery for \(url.lastPathComponent). Keep this window open and retry, \
                or use Save As after revealing the recovery copy.
                """
            )
        case .noActiveDocument:
            String(localized: "There is no active document.")
        case .unresolvedExternalConflict:
            String(localized: "Resolve the external file change before saving, or use Save As to keep this copy.")
        case let .backingFileUnavailable(issue):
            switch issue {
            case .missingOrMoved, .parentUnavailable:
                String(localized: "The backing file is no longer available. Use Save As to keep this copy.")
            case .permissionDenied:
                String(localized: "MacDown cannot access the backing file. Use Save As to keep this copy.")
            case .notRegularFile:
                String(localized: "The backing path is no longer a regular file. Use Save As to keep this copy.")
            case .ambiguousMove, .moveCollidesWithOpenDocument:
                String(localized: "MacDown could not safely follow the moved file. Use Save As to keep this copy.")
            case .readFailed:
                String(localized: "The backing file cannot be read safely. Use Save As to keep this copy.")
            }
        }
    }
}
