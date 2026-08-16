import Foundation

/// The state of a document's dirty flag and close-dirty prompt flow.
///
/// The machine is intentionally simple and synchronous at its core; IO is
/// delegated to `FileStore` and `RecoveryBuffer`.
public enum FileDocumentState: Sendable, Equatable {
    /// No unsaved changes.
    case clean
    /// Has unsaved changes.
    case dirty
    /// Dirty and the user is being asked how to resolve the close.
    case promptingClose
    /// An external change was detected; the user must choose how to reconcile.
    case conflict
}

/// The user's choice when closing a dirty document.
public enum CloseResolution: Sendable, Equatable {
    case save
    case discard
    case cancel
}

/// The user's choice when an external file change conflicts with in-memory edits.
public enum ConflictResolution: Sendable, Equatable {
    case keepMine
    case useExternal
    case cancel
}

public enum FileBackingIssue: Sendable, Equatable {
    case missingOrMoved
    case permissionDenied
    case parentUnavailable
    case notRegularFile
    case ambiguousMove
    case moveCollidesWithOpenDocument
    case readFailed(String)
}

public enum FileBackingState: Sendable, Equatable {
    case untitled
    case available
    case unavailable(FileBackingIssue)
}
