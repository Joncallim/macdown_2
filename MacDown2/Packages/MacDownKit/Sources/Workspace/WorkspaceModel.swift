import FileCore
import Foundation
import Observation

/// Sidebar sections displayed in the workspace shell.
public enum SidebarSection: String, Sendable, CaseIterable, Identifiable {
    case folder
    case outline

    public var id: String {
        rawValue
    }

    /// Order used on first launch and to fill gaps during reconciliation.
    public static var defaultOrder: [SidebarSection] {
        allCases
    }

    /// Drops unknown identifiers, appends missing cases in `allCases` order.
    public static func reconcile(_ stored: [String]) -> [SidebarSection] {
        var result: [SidebarSection] = []
        var seen: Set<String> = []
        for rawValue in stored {
            guard let section = SidebarSection(rawValue: rawValue),
                  seen.insert(section.id).inserted else { continue }
            result.append(section)
        }
        for section in SidebarSection.allCases where !seen.contains(section.id) {
            result.append(section)
        }
        return result
    }
}

/// The observable model behind the MacDown 2 workspace shell.
///
/// Responsibilities:
/// - Own the `TabStore` that tracks open tabs and the active document.
/// - Route File menu intents (`newDocument`, `openFile`, `save`, `close`, …).
/// - Expose command enablement state for SwiftUI `Commands`.
/// - Persist window UI state (sidebar visibility, section expansion).
/// - Coordinate session restore on first launch.
///
/// `WorkspaceModel` is `@MainActor` and lives in the SPM `Workspace` module.
/// The tab bar and other views live in the app target.
@MainActor
@Observable
public final class WorkspaceModel {
    /// The tab store that owns all open tabs.
    public let tabStore: TabStore

    /// The document currently shown in the content area.
    public var activeDocument: FileDocument? {
        tabStore.activeDocument
    }

    /// The folder opened via ⌘⇧O, if any. The actual folder tree UI is E09.
    public private(set) var folderURL: URL?

    /// The most recent error surfaced to the user. Views may present this.
    public private(set) var lastError: WorkspaceError?

    /// Whether the sidebar column is visible. Persisted via `stateStore`.
    public var sidebarVisible: Bool {
        didSet {
            stateStore.sidebarVisible = sidebarVisible
        }
    }

    /// Document-order of sidebar sections. Persisted via `stateStore`.
    public private(set) var sectionOrder: [SidebarSection]

    /// Cached expansion state so SwiftUI body evaluations do not hit
    /// `UserDefaults` on every read.
    private var sectionExpanded: [SidebarSection: Bool]

    public var hasActiveDocument: Bool {
        tabStore.hasActiveDocument
    }

    /// `true` if the active document can be saved right now.
    public var canSave: Bool {
        tabStore.canSave
    }

    /// `true` if the active tab exists and is not pinned.
    public var canClose: Bool {
        tabStore.canCloseActiveTab
    }

    private var stateStore: WorkspaceStateStoring
    private let panel: any FilePanelProviding

    public init(
        tabStore: TabStore? = nil,
        stateStore: WorkspaceStateStoring = WorkspaceStateStore(),
        panel: (any FilePanelProviding)? = nil
    ) {
        self.tabStore = tabStore ?? TabStore()
        self.stateStore = stateStore
        self.panel = panel ?? NoOpFilePanelProvider()
        folderURL = nil
        lastError = nil
        sidebarVisible = stateStore.sidebarVisible
        sectionOrder = SidebarSection.reconcile(stateStore.sidebarSectionOrder)
        sectionExpanded = Dictionary(uniqueKeysWithValues: SidebarSection.allCases.map { section in
            (section, stateStore.sidebarSectionExpanded[section.rawValue] ?? true)
        })
    }

    // MARK: - State store helpers

    public func isSectionExpanded(_ section: SidebarSection) -> Bool {
        sectionExpanded[section] ?? true
    }

    public func setSectionExpanded(_ section: SidebarSection, _ expanded: Bool) {
        sectionExpanded[section] = expanded
        stateStore.sidebarSectionExpanded[section.rawValue] = expanded
    }

    /// Reorders sidebar sections and persists the new order.
    public func moveSections(fromOffsets offsets: IndexSet, toOffset offset: Int) {
        var order = sectionOrder
        let moved = offsets.compactMap { order.indices.contains($0) ? order[$0] : nil }
        let remaining = order.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        let targetIndex = max(0, min(offset, remaining.count))
        order = Array(remaining[..<targetIndex] + moved + remaining[targetIndex...])
        sectionOrder = order
        stateStore.sidebarSectionOrder = order.map(\.rawValue)
    }

    // MARK: - Intents

    /// Creates a new untitled tab with a Markdown document.
    public func newDocument() {
        tabStore.newTab()
        lastError = nil
    }

    /// Opens an existing file chosen by the user into a new tab, or activates
    /// the existing tab if the file is already open.
    public func openFile() async {
        guard let url = await panel.chooseFile() else { return }
        let tab = await tabStore.openFileInTab(url)
        if tab == nil {
            lastError = .openFailed(underlying: .readFailed(underlying: CocoaError(.fileReadNoSuchFile)))
        } else {
            lastError = nil
        }
    }

    /// Opens a folder chosen by the user.
    public func openFolder() async {
        guard let url = await panel.chooseFolder() else { return }
        folderURL = url
    }

    /// Saves the active document. Untitled documents prompt for a location.
    public func save() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }

        if document.fileURL == nil {
            await saveAs()
            return
        }

        do {
            let saved = try document.save()
            tabStore.updateActiveDocument { _ in saved }
            lastError = nil
        } catch {
            lastError = .saveFailed(underlying: cast(error))
        }
    }

    /// Saves the active document to a user-chosen location.
    public func saveAs() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }

        let defaultName = document.fileURL?.lastPathComponent
            ?? "Untitled.\(document.format.extensions.first ?? "md")"
        guard let url = await panel.chooseSaveLocation(
            defaultName: defaultName,
            format: document.format
        ) else { return }

        do {
            let saved = try document.saveAs(url)
            tabStore.updateActiveDocument { _ in saved }
            await tabStore.activeDocument?.clearRecovery()
            lastError = nil
        } catch {
            lastError = .saveFailed(underlying: cast(error))
        }
    }

    /// Begins closing the active tab.
    public func requestCloseDocument() {
        tabStore.requestCloseActiveTab()
    }

    /// Resolves a dirty-close prompt for the active tab.
    public func resolveClose(_ resolution: CloseResolution) async {
        await tabStore.resolveClose(resolution) { [weak self] in
            await self?.saveInternalForClose()
            return self?.tabStore.activeDocument?.state == .clean
        }
    }

    // MARK: - Internal helpers

    private func saveInternalForClose() async {
        guard tabStore.activeDocument != nil else { return }
        await save()
    }

    private func cast(_ error: Error) -> FileStoreError {
        error as? FileStoreError ?? .readFailed(underlying: error)
    }
}
