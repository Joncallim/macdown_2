import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
import Observation
import SwiftUI
import Themes
import Workspace

extension EnvironmentValues {
    @Entry var windowCoordinator: WindowCoordinator?
    @Entry var themeController: ThemeController?
    @Entry var appSettings: AppSettingsModel?
}

// MARK: - Coordinator

/// Owns the global document pool and the native `NSWindow` controllers that
/// present each document as a tab.
@MainActor
@Observable
final class WindowCoordinator {
    enum TerminationRecoveryState: Equatable {
        case none
        case recoveryRequired
    }

    /// The model for the document currently shown in the key window.
    private(set) var keyModel: WorkspaceModel?

    // `controllers`, `sessionStore`, `themeController`, and `grammarRegistry`
    // are internal rather than private: `WindowCoordinator+SessionRestore.swift`
    // is a same-module extension in a separate file (split out to stay under
    // the type-body-length lint budget) and needs them.
    var controllers: [WindowController] = []
    let sessionStore: WorkspaceSessionStoring
    let panelProvider: NSFilePanelProvider
    let recoveryBuffer: RecoveryBuffer
    let themeController: ThemeController
    let grammarRegistry: GrammarRegistry
    let fileTreePreferences: FileTreePreferences
    let recentFolderRoots: RecentFolderRoots
    let appSettings: AppSettingsModel
    private let workspaceStateStore: any WorkspaceStateStoring
    private var hasRestoredSession = false
    private var saveTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var pendingNewDocumentTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Documents with an export currently in flight. Not `@ObservationIgnored`
    /// — `ExportCoordinator.canExportActiveDocument` reads this on every menu
    /// validation, and the menu item must grey out while its export runs.
    var exportingModels: Set<ObjectIdentifier> = []
    /// Stateless export orchestrator for the active document (E12). A computed
    /// property keeps it outside `@Observable` tracking; the value type means
    /// menu validation, which reads it on every evaluation, allocates nothing.
    var exportCoordinator: ExportCoordinator {
        ExportCoordinator(coordinator: self, themeController: themeController, appSettings: appSettings)
    }

    /// Changes whenever AppKit focus/input can have changed the responder used
    /// by the formatting commands.  SwiftUI commands read this through the
    /// command bridge, so menu validation is invalidated even though AppKit's
    /// first-responder chain is not an Observable value.
    private(set) var commandStateRevision = 0
    @ObservationIgnored var onNewDocumentLifetimePrepared: (@MainActor () async -> Void)?
    @ObservationIgnored var terminationRecoveryState: TerminationRecoveryState = .none
    @ObservationIgnored var terminationRecoveryController: WindowController?

    init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        panelProvider: NSFilePanelProvider = NSFilePanelProvider(),
        recoveryBuffer: RecoveryBuffer = .shared,
        themeController: ThemeController,
        grammarRegistry: GrammarRegistry,
        fileTreePreferences: FileTreePreferences,
        recentFolderRoots: RecentFolderRoots,
        appSettings: AppSettingsModel,
        workspaceStateStore: any WorkspaceStateStoring = WorkspaceStateStore()
    ) {
        self.sessionStore = sessionStore
        self.panelProvider = panelProvider
        self.recoveryBuffer = recoveryBuffer
        self.themeController = themeController
        self.grammarRegistry = grammarRegistry
        self.fileTreePreferences = fileTreePreferences
        self.recentFolderRoots = recentFolderRoots
        self.appSettings = appSettings
        self.workspaceStateStore = workspaceStateStore
    }

    // MARK: - Window lifecycle

    /// Creates a new untitled document window. When `addAsTab` is `true` and a
    /// key window exists, the new window is added as a tab of the key window.
    func newDocument(addAsTab: Bool = false) {
        let keyWindow = NSApp.keyWindow

        let model = makeWindowModel()
        let controller = WindowController(
            model: model,
            coordinator: self,
            themeController: themeController,
            grammarRegistry: grammarRegistry,
            fileTreePreferences: fileTreePreferences
        )
        addController(controller, addingAsTab: addAsTab, keyWindow: keyWindow)
        let key = ObjectIdentifier(controller)
        model.onManagedDocumentLifetimePrepared = { [weak self] in
            await self?.onNewDocumentLifetimePrepared?()
        }
        let encoding = Self.defaultEncoding(from: appSettings.formats)
        pendingNewDocumentTasks[key] = Task { @MainActor [weak self, weak controller] in
            defer { self?.pendingNewDocumentTasks[key] = nil }
            guard let self, let controller else { return }
            _ = await model.newManagedDocument(encoding: encoding) {
                !Task.isCancelled && self.controllers.contains { $0 === controller }
            }
        }
    }

    /// Opens a file in a new window, or activates the existing window if the
    /// same file is already open.
    func openDocument(
        at url: URL,
        folderRoot: URL? = nil,
        folderAccessURL: URL? = nil,
        folderSelectionURL: URL? = nil,
        folderRenameURL: URL? = nil
    ) async {
        if let existing = controllerForDocument(url: url), let window = existing.window {
            if let folderRoot, existing.fileTreeModel.root == nil {
                existing.model.setFolderRoot(folderRoot)
                await existing.fileTreeModel.setRoot(folderRoot, accessURL: folderAccessURL)
            }
            existing.fileTreeModel.selectedURL = folderSelectionURL
            existing.fileTreeModel.renamingURL = folderRenameURL
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
            return
        }

        let keyWindow = NSApp.keyWindow

        let model = makeWindowModel()
        let outcome = await model.tabStore.openFileInTab(url)
        model.setFolderRoot(folderRoot)

        guard !model.tabStore.tabs.isEmpty else {
            if case let .failure(error) = outcome {
                presentOpenFailure(error, url: url)
            }
            return
        }
        let controller = WindowController(
            model: model,
            coordinator: self,
            themeController: themeController,
            grammarRegistry: grammarRegistry,
            fileTreePreferences: fileTreePreferences
        )
        if let folderRoot {
            await controller.fileTreeModel.setRoot(folderRoot, accessURL: folderAccessURL)
        }
        controller.fileTreeModel.selectedURL = folderSelectionURL
        controller.fileTreeModel.renamingURL = folderRenameURL
        addController(controller, addingAsTab: true, keyWindow: keyWindow)
    }

    /// Shows the open panel and opens the chosen file.
    func openFile() {
        Task { @MainActor in
            guard let url = await panelProvider.chooseFile() else { return }
            await openDocument(at: url)
        }
    }

    /// Closes the tab/window that is currently key.
    func closeKeyWindow() {
        guard let controller = controllers.first(where: { $0.window?.isKeyWindow ?? false }),
              let window = controller.window else { return }
        // Call windowShouldClose directly instead of NSWindow.performClose. Under
        // native tabbing, performClose can trigger tab-group selection changes even
        // when windowShouldClose returns false (dirty document), causing a sibling
        // tab to erroneously become key after the sheet is dismissed.
        if controller.windowShouldClose(window) {
            controller.close()
        }
    }

    func saveKeyDocument() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        Task { await controller.saveDocument() }
    }

    func saveKeyDocumentAs() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        Task { await controller.saveDocumentAs() }
    }

    /// Selects the next tab in the key window's native tab group.
    func selectNextTab() {
        NSApp.keyWindow?.selectNextTab(nil)
        commandStateDidChange()
    }

    /// Selects the previous tab in the key window's native tab group.
    func selectPreviousTab() {
        NSApp.keyWindow?.selectPreviousTab(nil)
        commandStateDidChange()
    }

    /// Selects a tab by index in the key window's native tab group. Index 8
    /// (⌘9) always means the last tab.
    func selectTab(at index: Int) {
        guard let tabGroup = NSApp.keyWindow?.tabGroup, !tabGroup.windows.isEmpty else { return }
        let targetIndex = (index == 8) ? tabGroup.windows.count - 1 : min(index, tabGroup.windows.count - 1)
        let targetWindow = tabGroup.windows[targetIndex]
        tabGroup.selectedWindow = targetWindow
        // Refresh immediately; the window delegate will also reconcile the key
        // model once AppKit finishes the native-tab transition.
        targetWindow.makeKeyAndOrderFront(nil)
        commandStateDidChange()
    }

    /// `true` if the key window's tab group has more than one tab.
    var keyWindowHasMultipleTabs: Bool {
        guard let count = NSApp.keyWindow?.tabGroup?.windows.count else { return false }
        return count > 1
    }

    /// `true` if the key window's tab group has a tab at the given index.
    func keyWindowHasTab(at index: Int) -> Bool {
        guard let count = NSApp.keyWindow?.tabGroup?.windows.count, count > 0 else { return false }
        if index == 8 {
            return true
        }
        return index < count
    }

    /// ⌃⌘O (D11). Reveals the outline in the key window, then hands off to
    /// its `OutlineController` — focusing a hidden list is a dead shortcut,
    /// so both the sidebar and the outline's own disclosure are ensured open
    /// first. JSON documents route to the JSON outline channel.
    func focusOutline() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        controller.model.sidebarVisible = true
        controller.model.setSectionExpanded(.outline, true)
        if controller.model.activeDocument?.format.id == "json" {
            controller.outlineController.requestJSONFocus()
        } else {
            controller.outlineController.requestFocus()
        }
    }

    // MARK: - Session

    /// Schedules a session save, debounced so rapid changes coalesce into one
    /// write. Call this after any structural or document change.
    func scheduleSaveSession() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await saveSession()
        }
    }

    /// Begins the launch-time session restore. A short grace period lets a
    /// pending `application(_:openFiles:)` arrive before the restore decision;
    /// `isDocumentOpenPending` is evaluated after that delay. The work is
    /// tracked in `restoreTask` so ``ensureWindowExistsForReopen()`` can await
    /// it instead of racing a new window into existence ahead of the restored
    /// session.
    func scheduleSessionRestore(isDocumentOpenPending: @escaping @MainActor () -> Bool) {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        restoreTask = Task { @MainActor [weak self] in
            // Give `application(_:openFiles:)` a few run-loop ticks to arrive
            // before we fall back to restoring the previous session.
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled, !isDocumentOpenPending() else { return }
            await restoreSession()
        }
    }

    /// Awaits any in-flight session restore, then creates an untitled window
    /// if no document window exists. Used by the reopen handler so a reopen
    /// event landing before the restored windows appear does not spawn a
    /// spurious untitled window.
    func ensureWindowExistsForReopen() async {
        await restoreTask?.value
        guard controllers.isEmpty else { return }
        newDocument()
    }

    /// Restores the saved session, creating one window per document and
    /// grouping them as tabs in a single native tab group. Falls back to an
    /// untitled window when there is nothing to restore.
    ///
    /// See `WindowCoordinator+SessionRestore.swift` for the rest of the
    /// restore pipeline — split out to keep this file under the type-body-
    /// length lint budget.
    func restoreSession() async {
        let tempStore = TabStore(sessionStore: sessionStore)
        await tempStore.restoreSessionIfNeeded()

        guard !tempStore.tabs.isEmpty else {
            newDocument()
            return
        }

        let (firstController, _) = restore(tabs: tempStore.tabs)
        activate(controller: firstController, activeID: tempStore.activeTabID)
        updateKeyModel()
    }

    // MARK: - Internal helpers

    func removeController(_ controller: WindowController) {
        pendingNewDocumentTasks.removeValue(forKey: ObjectIdentifier(controller))?.cancel()
        controllers.removeAll { $0 === controller }
        scheduleSaveSession()
        updateKeyModel()
    }

    private func addController(
        _ controller: WindowController,
        addingAsTab: Bool,
        keyWindow: NSWindow? = nil
    ) {
        controllers.append(controller)

        if addingAsTab, let key = keyWindow ?? NSApp.keyWindow, key != controller.window, let tab = controller.window {
            key.addTabbedWindow(tab, ordered: .above)
        }

        controller.showWindow(nil)
        scheduleSaveSession()
        updateKeyModel()
    }

    func makeWindowModel(panel: (any FilePanelProviding)? = nil) -> WorkspaceModel {
        let tabStore = TabStore(sessionStore: NoOpSessionStore(), recoveryBuffer: recoveryBuffer)
        let model = WorkspaceModel(
            tabStore: tabStore,
            stateStore: workspaceStateStore,
            panel: panel ?? panelProvider
        )
        model.setSaveAsSessionPublisher { [weak self, weak model] in
            guard let self, let model else { return false }
            let result = await saveSessionResult(allowingSaveAsPublicationFor: model)
            return result.persisted
        }
        tabStore.setRenameSessionPublisher { [weak self, weak model] in
            guard let self, let model else { return false }
            return await saveSessionResult(allowingSaveAsPublicationFor: model).persisted
        }
        return model
    }

    func updateKeyModel() {
        keyModel = controllers.first { $0.window == NSApp.keyWindow }?.model
        commandStateDidChange()
    }

    /// Invalidates SwiftUI command validation after AppKit has processed an
    /// event that may have changed first responder or the key window.
    func commandStateDidChange() {
        commandStateRevision &+= 1
    }
}

// MARK: - Session snapshot

struct TabSnapshot {
    let record: TabRecord
    let documentID: String
    let documentText: String
    let documentState: FileDocumentState
    let documentGeneration: UInt
    let documentRecoveryEpoch: UUID
}
