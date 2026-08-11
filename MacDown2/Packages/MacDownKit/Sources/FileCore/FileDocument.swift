import Foundation
import UniformTypeIdentifiers

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

/// Represents an open document and its lifecycle state.
///
/// `FileDocument` is a value type: mutating the state machine returns a new
/// instance, keeping the core pure and synchronous. IO is performed at the
/// edges by `FileStore` and `RecoveryBuffer`, which are injected so tests can
/// substitute them.
public struct FileDocument: Sendable {
    /// A stable identifier. For saved files this is the file URL's absolute
    /// string; for untitled documents it is a generated UUID.
    public private(set) var id: String

    /// The URL of the file on disk, or `nil` for untitled documents.
    public var fileURL: URL?

    /// The current text content of the document.
    public var text: String

    /// The format associated with this document.
    public private(set) var format: FileFormat

    /// The current lifecycle state.
    public var state: FileDocumentState

    public private(set) var lastKnownRevision: FileRevision?
    public private(set) var pendingExternalRevision: FileRevision?
    public private(set) var backingState: FileBackingState

    /// Monotonically advances for every visible document-state transition.
    /// Async callers use this to reject ABA-shaped stale completions where the
    /// text and state happen to return to their original values.
    public private(set) var mutationGeneration: UInt

    public var lastKnownModificationDate: Date? {
        lastKnownRevision?.modificationDate
    }

    /// The store used for disk IO. Injected to allow test doubles.
    public let fileStore: FileStore

    /// The recovery buffer used for autosave/recovery of untitled documents.
    /// Injected to allow tests to use an isolated directory.
    public let recoveryBuffer: RecoveryBuffer
    /// Distinguishes separate lifetimes that reuse the same URL-derived ID.
    /// Globally unique recovery lifetime, persisted with the session. Unlike a
    /// process-local counter it cannot collide after relaunch.
    public private(set) var recoveryEpoch: UUID

    /// Creates a new document, optionally backed by an existing file.
    public init(
        fileURL: URL? = nil,
        text: String = "",
        format: FileFormat? = nil,
        fileStore: FileStore = FileStore(),
        recoveryBuffer: RecoveryBuffer = .shared,
        documentID: String? = nil,
        recoveryEpoch: UUID? = nil
    ) {
        let normalizedURL = fileURL?.standardizedFileURL
        self.fileURL = normalizedURL
        self.text = text
        self.fileStore = fileStore
        self.recoveryBuffer = recoveryBuffer
        // Compatibility construction remains synchronous for pure state
        // tests and legacy callers. Production creation uses `create`, which
        // obtains a managed epoch from `RecoveryBuffer` after loading its
        // durable high-water ledger.
        self.recoveryEpoch = recoveryEpoch ?? UUID()
        state = .clean
        backingState = normalizedURL == nil ? .untitled : .available
        lastKnownRevision = nil
        pendingExternalRevision = nil
        mutationGeneration = 0

        if let normalizedURL {
            id = normalizedURL.absoluteString
            self.format = format ?? FileFormat.format(for: normalizedURL, in: FileFormatRegistry())
                ?? FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" }
                ?? FileFormat(id: "plaintext", name: "Plain Text", utType: .plainText, extensions: ["txt"])
        } else {
            id = documentID ?? UUID().uuidString
            self.format = format ?? FileFormatRegistry.defaultFormats.first { $0.id == "markdown" }
                ?? FileFormat(
                    id: "markdown",
                    name: "Markdown",
                    utType: UTType(filenameExtension: "md") ?? .plainText,
                    extensions: ["md"],
                    highlightLanguageID: "markdown",
                    previewCapability: .rendered
                )
        }
    }

    // MARK: - State transitions

    /// Marks the document as clean (used after a successful save or discard).
    public func markClean() -> FileDocument {
        var copy = self
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Begins the close flow for a dirty document, transitioning to prompting.
    public func requestClose() -> (document: FileDocument, resolution: CloseResolution?) {
        var copy = self
        switch state {
        case .clean:
            return (copy, .discard)
        case .dirty:
            copy.state = .promptingClose
            copy.advanceMutation()
            return (copy, nil)
        case .conflict:
            // A conflict has a distinct close flow. Do not erase that fact by
            // converting it to an ordinary dirty-close prompt.
            return (copy, nil)
        case .promptingClose:
            return (copy, nil)
        }
    }

    /// Resolves the close prompt.
    public func resolveClose(_ resolution: CloseResolution) -> FileDocument {
        var copy = self
        switch resolution {
        case .save, .discard:
            copy.state = .clean
        case .cancel:
            // Only a document that was actually prompting to close returns to
            // `.dirty`. Guard against dirtying an already-clean document if
            // `resolveClose(.cancel)` is ever called out of the prompt flow.
            copy.state = (state == .promptingClose) ? .dirty : state
        }
        if copy.state != state {
            copy.advanceMutation()
        }
        return copy
    }

    // MARK: - File IO

    /// Loads content from the document's `fileURL` into a new instance with `text` set.
    public func load() throws(FileStoreError) -> FileDocument {
        guard let fileURL else {
            throw .invalidURL
        }
        let snapshot = try fileStore.readSnapshot(from: fileURL)
        var copy = self
        copy.text = snapshot.text
        copy.lastKnownRevision = snapshot.revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Saves the current `text` to the document's `fileURL`.
    public func save() throws(FileStoreError) -> FileDocument {
        try saving(expectedRevision: lastKnownRevision)
    }

    /// Saves using a caller-owned baseline. The workspace save serializer uses
    /// this to let a later queued save adopt the revision accepted by an
    /// earlier save without losing edits made in between.
    public func saving(expectedRevision: FileRevision?) throws(FileStoreError) -> FileDocument {
        guard let fileURL else {
            // Untitled documents are not saved to disk; their recovery buffer
            // is maintained separately by `autosave()`.
            throw .invalidURL
        }

        let revision = try fileStore.write(text, to: fileURL, expectedRevision: expectedRevision)
        var copy = self
        copy.lastKnownRevision = revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Saves the current text to a new URL and updates the document identity.
    public func saveAs(_ url: URL) throws(FileStoreError) -> FileDocument {
        try saveAs(url, recoveryEpoch: UUID())
    }

    /// Saves to a new URL while adopting a caller-prepared recovery lifetime.
    /// Workspace production paths obtain this epoch from `RecoveryBuffer`
    /// before entering the write lane, so the resulting identity participates
    /// in the durable bounded-generation protocol.
    public func saveAs(_ url: URL, recoveryEpoch: UUID) throws(FileStoreError) -> FileDocument {
        let destination = url.standardizedFileURL
        let revision = try fileStore.write(text, to: destination)
        var copy = self
        copy.fileURL = destination
        copy.id = destination.absoluteString
        // A URL-derived recovery key denotes a document lifetime, not just a
        // pathname. Save As starts a fresh lifetime so queued recovery work
        // from the former identity cannot be admitted under the new key.
        copy.recoveryEpoch = recoveryEpoch
        copy.format = Self.format(for: destination)
        copy.lastKnownRevision = revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Adopts a completed Save As destination without discarding edits made
    /// while that write was in flight. `saved` contributes the newly admitted
    /// URL, format, and disk revision; this descendant contributes the newer
    /// text and remains dirty when it differs from the published text.
    public func rebindingSavedDestination(from saved: FileDocument) -> FileDocument {
        var copy = saved
        copy.text = text
        copy.state = text == saved.text ? .clean : .dirty
        // Preserve the fact that this is a post-save local transition while
        // making it newer than both inputs for recovery ordering.
        copy.mutationGeneration = max(mutationGeneration, saved.mutationGeneration)
        copy.advanceMutation()
        return copy
    }

    /// Re-points a file-backed document after an in-app move or rename.
    /// This intentionally performs no IO; the caller has already completed it.
    public func renamed(to url: URL) -> FileDocument {
        renamed(to: url, recoveryEpoch: UUID())
    }

    /// Re-points a document using a caller-prepared recovery lifetime.
    /// Production rename/move paths use an epoch minted by `RecoveryBuffer`
    /// so a relaunch cannot confuse this identity with a legacy random UUID.
    public func renamed(to url: URL, recoveryEpoch: UUID) -> FileDocument {
        let destination = url.standardizedFileURL
        var copy = self
        copy.fileURL = destination
        copy.id = destination.absoluteString
        // The accepted identity changed. Give recovery writes for this
        // lifetime a new epoch before the controller migrates the buffer.
        copy.recoveryEpoch = recoveryEpoch
        copy.format = Self.format(for: destination)
        if let revision = copy.lastKnownRevision {
            copy.lastKnownRevision = FileRevision(
                url: destination,
                modificationDate: revision.modificationDate,
                fileSize: revision.fileSize,
                fileObjectID: revision.fileObjectID,
                sha256: revision.sha256
            )
        }
        copy.advanceMutation()
        return copy
    }

    /// Restores a document's original visible identity after a multi-document
    /// recovery migration fails. The recovery lifetime must change because the
    /// failed batch has already durably retired the original lifetime; the URL,
    /// document ID, text, and user-visible state remain unchanged.
    public func withReplacementRecoveryLifetime(_ epoch: UUID) -> FileDocument {
        var copy = self
        copy.recoveryEpoch = epoch
        copy.advanceMutation()
        // The reverse migration wrote the recovery record using the renamed
        // descendant's generation. Advance once more so the repaired source
        // lifetime can publish an equal-text session snapshot without being
        // mistaken for that prior write.
        copy.advanceMutation()
        return copy
    }

    /// Keeps the visible identity while replacing a recovery lifetime that was
    /// retired during a failed reverse migration.
    public func withFreshRecoveryLifetime() -> FileDocument {
        withReplacementRecoveryLifetime(UUID())
    }

    // MARK: - Autosave / recovery

    /// Writes a recovery copy if this is an untitled document.
    public func autosave() async {
        guard fileURL == nil else { return }
        _ = try? await recoveryBuffer.saveCurrentLifetime(
            content: text,
            for: id,
            version: mutationGeneration,
            epoch: recoveryEpoch
        )
    }

    /// Loads the recovery copy for an untitled document, if present.
    public func loadRecovery() async -> String? {
        guard fileURL == nil else { return nil }
        return try? await recoveryBuffer.load(for: id)
    }

    /// Clears the recovery copy (call after a successful save-as or explicit discard).
    public func clearRecovery() async {
        await recoveryBuffer.remove(for: id, version: mutationGeneration, epoch: recoveryEpoch)
    }

    // MARK: - External change detection

    // MARK: - Helpers

    private static func format(for url: URL) -> FileFormat {
        FileFormat.format(for: url, in: FileFormatRegistry())
            ?? FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" }
            ?? FileFormat(id: "plaintext", name: "Plain Text", utType: .plainText, extensions: ["txt"])
    }

    /// Internal mutation seam so the public state remains externally read-only
    /// while pure transitions can stay in their own source file.
    mutating func applyExternalState(
        lastKnownRevision: FileRevision? = nil,
        setLastKnownRevision: Bool = false,
        pendingExternalRevision: FileRevision? = nil,
        setPendingExternalRevision: Bool = false,
        backingState: FileBackingState? = nil
    ) {
        if setLastKnownRevision {
            self.lastKnownRevision = lastKnownRevision
        }
        if setPendingExternalRevision {
            self.pendingExternalRevision = pendingExternalRevision
        }
        if let backingState {
            self.backingState = backingState
        }
    }

    mutating func advanceMutation() {
        mutationGeneration &+= 1
    }
}
