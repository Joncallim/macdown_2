import FileCore
import Foundation
import Observation

/// One open tab.
///
/// `id` is a stable UUID assigned at creation and used for session restore.
/// It is intentionally separate from `document.id` (the file URL string for
/// file-backed documents and the recovery key for untitled documents) so the
/// session schema stays stable across save-as and untitled recovery buffer keys.
public struct WorkspaceTab: Identifiable, Sendable {
    public let id: UUID
    public var document: FileDocument
    public var isPinned: Bool

    /// Transient editor state captured at session-save time. Applied by the
    /// app target after restore; not used by `TabStore` itself.
    ///
    /// `cursorPosition` is the UTF-16 offset of the start of the editor
    /// selection (the caret when `selectionLength` is zero). `selectionLength`
    /// is the number of UTF-16 code units selected. Together they reconstruct
    /// the full `NSRange` on restore.
    public var cursorPosition: Int?
    public var selectionLength: Int?
    public var scrollOffset: Double?

    /// The editor/preview layout for this tab. Persisted with the session
    /// because it is part of the document workspace, not global UI state.
    public var previewLayout: PreviewLayoutMode?

    /// The preview pane's display mode for this tab (e.g. HTML source vs
    /// rendered), or `nil` to use the format's default mode. Persisted with
    /// the session; Save As format transitions invalidate it (the view resets
    /// it to `nil` when the format's capability changes).
    public var previewMode: PreviewMode?

    /// Per-window folder root persisted alongside this native-window tab.
    public var folderRootBookmark: Data?
    public var folderRootAlias: URL?

    public init(
        id: UUID = UUID(),
        document: FileDocument,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        selectionLength: Int? = nil,
        scrollOffset: Double? = nil,
        previewLayout: PreviewLayoutMode? = nil,
        previewMode: PreviewMode? = nil,
        folderRootBookmark: Data? = nil,
        folderRootAlias: URL? = nil
    ) {
        self.id = id
        self.document = document
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
        self.previewLayout = previewLayout
        self.previewMode = previewMode
        self.folderRootBookmark = folderRootBookmark
        self.folderRootAlias = folderRootAlias
    }
}

public enum DeletedDocumentOutcome: Sendable, Equatable {
    case notOpen
    case closedCleanTab(UUID)
    case needsPrompt(UUID)
}

/// In-app tab state: ordered tabs, active tab, dirty-close prompts, and session
/// persistence.
///
/// `TabStore` is `@MainActor` because it is observed by SwiftUI and because
/// `WorkspaceSessionStoring` implementations are main-actor isolated.
@MainActor
@Observable
public final class TabStore {
    /// All open tabs, ordered left-to-right. Pinned tabs always precede
    /// unpinned tabs.
    public internal(set) var tabs: [WorkspaceTab]

    /// The tab currently shown in the content area.
    public internal(set) var activeTabID: UUID?

    /// Non-nil while the dirty-close alert should be shown for this tab.
    public internal(set) var pendingCloseTabID: UUID?

    /// The active tab, if any.
    public var activeTab: WorkspaceTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    /// The document of the active tab, if any.
    public var activeDocument: FileDocument? {
        activeTab?.document
    }

    public var hasActiveDocument: Bool {
        activeTab != nil
    }

    /// `true` if the active document can be saved right now.
    public var canSave: Bool {
        guard let document = activeDocument else { return false }
        if document.state == .conflict {
            return false
        }
        if document.fileURL == nil {
            return !document.text.isEmpty
        }
        switch document.backingState {
        case .available, .unavailable:
            return document.state == .dirty
        case .untitled:
            return !document.text.isEmpty
        }
    }

    /// `true` if the active tab exists and is not pinned.
    public var canCloseActiveTab: Bool {
        guard let activeTab, !activeTab.isPinned else { return false }
        return true
    }

    let sessionStore: WorkspaceSessionStoring
    let recoveryBuffer: RecoveryBuffer
    var closeQueue: [UUID]
    var saveTask: Task<Void, Never>?
    var lastPublishedSession: WorkspaceSession?
    var hasRestoredSession = false
    private var openRequestGeneration: UInt = 0
    /// Test seam for an edit arriving after a rename's managed epoch is
    /// prepared but before the batch captures a replacement snapshot.
    var onRenameReplacementPrepared: (@MainActor (FileDocument) async -> Void)?
    /// Test seam for an edit after a dirty tab's recovery migration completes
    /// but before the batch may publish its prepared replacement.
    var onRenameRecoveryMigrationCompleted: (@MainActor (FileDocument) async -> Void)?
    /// Test seam for a race while a stale source is being preserved after a
    /// recovery migration. Production leaves this unset.
    var onRenamePreservationPrepared: (@MainActor (FileDocument) async -> Void)?
    /// The native-window coordinator owns the canonical multi-window session
    /// file. It installs this verified publication boundary for renames.
    var renameSessionPublisher: (@MainActor () async -> Bool)?

    public init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        recoveryBuffer: RecoveryBuffer = .shared
    ) {
        self.sessionStore = sessionStore
        self.recoveryBuffer = recoveryBuffer
        tabs = []
        activeTabID = nil
        pendingCloseTabID = nil
        closeQueue = []
        lastPublishedSession = nil
    }

    public func setRenameSessionPublisher(_ publisher: @escaping @MainActor () async -> Bool) {
        renameSessionPublisher = publisher
    }

    // MARK: - Lifecycle intents

    /// Creates a new Markdown tab and activates it.
    ///
    /// The optional `id` and `document` are used by session restore so the
    /// restored tab keeps its original UUID and loaded document.
    public func newTab(id: UUID? = nil, document: FileDocument? = nil) {
        let tab = WorkspaceTab(
            id: id ?? UUID(),
            document: document ?? FileDocument(recoveryBuffer: recoveryBuffer)
        )
        tabs.append(tab)
        activeTabID = tab.id
        persist()
    }

    /// Opens a file into a tab. If a tab for the same standardized file URL
    /// already exists, that tab is activated and no new tab is created.
    /// Returns the resulting tab, or `nil` if the file could not be loaded.
    @discardableResult
    public func openFileInTab(_ url: URL) async -> WorkspaceTab? {
        let standardized = url.standardizedFileURL
        openRequestGeneration &+= 1
        let requestGeneration = openRequestGeneration

        if let existing = tabs.first(where: { $0.document.fileURL?.standardizedFileURL == standardized }) {
            if requestGeneration == openRequestGeneration {
                activeTabID = existing.id
            }
            persist()
            return existing
        }

        let document: FileDocument
        do {
            document = try await FileDocument.create(fileURL: url, recoveryBuffer: recoveryBuffer)
        } catch {
            return nil
        }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try document.load()
            }.value
            // The await above lets another intent open/activate this file.
            // Reuse that tab rather than publishing a duplicate completion.
            if let existing = tabs.first(where: { $0.document.fileURL?.standardizedFileURL == standardized }) {
                if requestGeneration == openRequestGeneration {
                    activeTabID = existing.id
                }
                persist()
                return existing
            }
            let tab = WorkspaceTab(document: loaded)
            tabs.append(tab)
            if requestGeneration == openRequestGeneration {
                activeTabID = tab.id
            }
            persist()
            return tab
        } catch {
            return nil
        }
    }

    // MARK: - Document write-back

    /// Applies a transform to the active document and writes the returned value
    /// back. `FileDocument` is a value type; mutations return new instances.
    public func updateActiveDocument(_ transform: (FileDocument) -> FileDocument) {
        guard let activeTabID, let index = tabIndex(of: activeTabID) else { return }
        tabs[index].document = transform(tabs[index].document)
        persist()
    }

    // MARK: - Session persistence

    /// Restores the prior session once. Missing files drop tabs; corrupt JSON
    /// yields an empty session. Never throws and never blocks launch.
    public func restoreSessionIfNeeded() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true

        guard let session = sessionStore.loadSession() else { return }
        guard session.version == WorkspaceSession.currentVersion else { return }

        var restoredTabs: [WorkspaceTab] = []
        for record in session.tabs {
            if let tab = await restoreTab(from: record) {
                restoredTabs.append(tab)
            }
        }

        tabs = restoredTabs

        if let activeTabID = session.activeTabID, tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = activeTabID
        } else if let first = tabs.first {
            activeTabID = first.id
        } else {
            activeTabID = nil
        }

        await acknowledgePendingRecoveryMigrations()
        await saveSession()
    }

    /// Autosaves every dirty tab's text before publishing session identities.
    /// `.promptingClose` counts as dirty here too — `requestClose(_:)` calls
    /// `persist()` the moment a tab enters that state, so this is the
    /// autosave that is supposed to protect its edits while the close prompt
    /// is up and undecided.
    /// If recovery cannot be verified, the prior on-disk session remains the
    /// last-good session rather than pointing at an unrecoverable lifetime.
    @discardableResult
    public func saveSession() async -> Bool {
        for tab in tabs
            where tab.document.state == .dirty || tab.document.state == .conflict
            || tab.document.state == .promptingClose {
            // Snapshot before suspension. Besides keeping recovery I/O off the
            // observed main-actor store, this prevents a borrowed array entry
            // from crossing the actor hop while a later edit replaces it.
            let content = String(tab.document.text)
            let documentID = String(tab.document.id)
            let generation = tab.document.mutationGeneration
            let lifetime = tab.document.recoveryEpoch
            let recoveryBuffer = tab.document.recoveryBuffer
            let persistenceTask: Task<Bool, Never> = Task.detached(priority: .utility) {
                do {
                    return try await recoveryBuffer.saveCurrentLifetime(
                        content: content,
                        for: documentID,
                        version: generation,
                        epoch: lifetime
                    )
                } catch {
                    return false
                }
            }
            let persisted = await persistenceTask.value
            if !persisted {
                // A migration may have already written this exact immutable
                // snapshot at the same version. It is safe to publish only
                // when the recovery record still verifies the captured text;
                // a stale/rejected write never gets this exception.
                guard let recovered = try? await recoveryBuffer.load(for: documentID, epoch: lifetime),
                      recovered == content
                else { return false }
            }
        }
        let session = currentSession()
        sessionStore.saveSession(session)
        lastPublishedSession = session
        return true
    }
}
