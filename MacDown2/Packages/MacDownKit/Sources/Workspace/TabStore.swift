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

    public init(
        id: UUID = UUID(),
        document: FileDocument,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        selectionLength: Int? = nil,
        scrollOffset: Double? = nil
    ) {
        self.id = id
        self.document = document
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
    }
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
        if document.fileURL == nil {
            return !document.text.isEmpty
        }
        return document.state == .dirty || document.state == .conflict
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
    var hasRestoredSession = false

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

        if let existing = tabs.first(where: { $0.document.fileURL?.standardizedFileURL == standardized }) {
            activeTabID = existing.id
            persist()
            return existing
        }

        let document = FileDocument(fileURL: url, recoveryBuffer: recoveryBuffer)
        do {
            let loaded = try document.load()
            let tab = WorkspaceTab(document: loaded)
            tabs.append(tab)
            activeTabID = tab.id
            persist()
            return tab
        } catch {
            return nil
        }
    }

    // MARK: - Arrangement & navigation

    public func activate(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        persist()
    }

    public func selectNextTab() {
        guard let activeTabID, tabs.count > 1 else { return }
        guard let index = tabIndex(of: activeTabID) else { return }
        let nextIndex = (index + 1) % tabs.count
        activate(tabs[nextIndex].id)
    }

    public func selectPreviousTab() {
        guard let activeTabID, tabs.count > 1 else { return }
        guard let index = tabIndex(of: activeTabID) else { return }
        let previousIndex = (index - 1 + tabs.count) % tabs.count
        activate(tabs[previousIndex].id)
    }

    /// Selects a tab by visible index. Index 8 (⌘9) always means the last tab.
    public func selectTab(at index: Int) {
        guard !tabs.isEmpty else { return }
        let targetIndex = (index == 8) ? tabs.count - 1 : min(index, tabs.count - 1)
        guard targetIndex >= 0 else { return }
        activate(tabs[targetIndex].id)
    }

    public func togglePin(_ id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        let wasPinned = tabs[index].isPinned
        let tab = tabs.remove(at: index)
        let pinnedCount = tabs.filter(\.isPinned).count

        if wasPinned {
            tabs.insert(WorkspaceTab(id: tab.id, document: tab.document, isPinned: false), at: pinnedCount)
        } else {
            tabs.insert(WorkspaceTab(id: tab.id, document: tab.document, isPinned: true), at: pinnedCount)
        }

        persist()
    }

    /// Moves a tab from one visible index to another, clamping the destination
    /// so pinned tabs never leave the pinned region and unpinned tabs never
    /// enter it.
    public func moveTab(from source: Int, to destination: Int) {
        guard source >= 0, source < tabs.count else { return }
        let sourceTab = tabs[source]
        let pinnedCount = tabs.filter(\.isPinned).count

        let clampedDestination: Int = if sourceTab.isPinned {
            min(max(destination, 0), pinnedCount - 1)
        } else {
            min(max(destination, pinnedCount), tabs.count - 1)
        }

        guard clampedDestination != source else { return }
        let tab = tabs.remove(at: source)
        let insertIndex = clampedDestination > source ? clampedDestination : clampedDestination
        tabs.insert(tab, at: insertIndex)
        persist()
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

        await saveSession()
    }

    /// Autosaves every dirty tab's text to the recovery buffer, then writes the
    /// session JSON. Failures are swallowed.
    public func saveSession() async {
        for tab in tabs where tab.document.state == .dirty || tab.document.state == .conflict {
            try? await recoveryBuffer.save(content: tab.document.text, for: tab.document.id)
        }

        sessionStore.saveSession(currentSession())
    }

    // MARK: - Internal helpers

    func tabIndex(of id: UUID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    func removeTab(at index: Int) {
        let removedID = tabs[index].id
        tabs.remove(at: index)

        if activeTabID == removedID {
            activeTabID = nextActiveTabID(afterRemovingTabAt: index)
        }
    }

    func nextActiveTabID(afterRemovingTabAt removedIndex: Int) -> UUID? {
        for offset in 1 ..< max(removedIndex + 1, tabs.count - removedIndex + 1) {
            let leftIndex = removedIndex - offset
            if leftIndex >= 0, leftIndex < tabs.count {
                return tabs[leftIndex].id
            }
            let rightIndex = removedIndex + offset - 1
            if rightIndex >= 0, rightIndex < tabs.count {
                return tabs[rightIndex].id
            }
        }
        return nil
    }

    func persist() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await saveSession()
        }
    }
}
