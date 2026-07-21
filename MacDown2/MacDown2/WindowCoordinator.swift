import AppKit
import EditorCore
import FileCore
import Foundation
import Observation
import SwiftUI
import Workspace

extension EnvironmentValues {
    @Entry var windowCoordinator: WindowCoordinator?
}

// MARK: - Coordinator

/// Owns the global document pool and the native `NSWindow` controllers that
/// present each document as a tab.
@MainActor
@Observable
final class WindowCoordinator {
    /// The model for the document currently shown in the key window.
    private(set) var keyModel: WorkspaceModel?

    private(set) var controllers: [WindowController] = []
    private let sessionStore: WorkspaceSessionStoring
    private let panelProvider: NSFilePanelProvider
    private let recoveryBuffer: RecoveryBuffer
    private var hasRestoredSession = false
    private var saveTask: Task<Void, Never>?

    init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        panelProvider: NSFilePanelProvider = NSFilePanelProvider(),
        recoveryBuffer: RecoveryBuffer = .shared
    ) {
        self.sessionStore = sessionStore
        self.panelProvider = panelProvider
        self.recoveryBuffer = recoveryBuffer
    }

    // MARK: - Window lifecycle

    /// Creates a new untitled document window. When `addAsTab` is `true` and a
    /// key window exists, the new window is added as a tab of the key window.
    func newDocument(addAsTab: Bool = false) {
        let keyWindow = NSApp.keyWindow

        let model = makeWindowModel()
        model.newDocument()
        let controller = WindowController(model: model, coordinator: self)
        addController(controller, addingAsTab: addAsTab, keyWindow: keyWindow)
    }

    /// Opens a file in a new window, or activates the existing window if the
    /// same file is already open.
    func openDocument(at url: URL) async {
        if let existing = controllerForDocument(url: url), let window = existing.window {
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
            return
        }

        let keyWindow = NSApp.keyWindow

        let model = makeWindowModel()
        _ = await model.tabStore.openFileInTab(url)

        guard !model.tabStore.tabs.isEmpty else { return }
        let controller = WindowController(model: model, coordinator: self)
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

    /// Selects the next tab in the key window's native tab group.
    func selectNextTab() {
        NSApp.keyWindow?.selectNextTab(nil)
    }

    /// Selects the previous tab in the key window's native tab group.
    func selectPreviousTab() {
        NSApp.keyWindow?.selectPreviousTab(nil)
    }

    /// Selects a tab by index in the key window's native tab group. Index 8
    /// (⌘9) always means the last tab.
    func selectTab(at index: Int) {
        guard let tabGroup = NSApp.keyWindow?.tabGroup, !tabGroup.windows.isEmpty else { return }
        let targetIndex = (index == 8) ? tabGroup.windows.count - 1 : min(index, tabGroup.windows.count - 1)
        let targetWindow = tabGroup.windows[targetIndex]
        tabGroup.selectedWindow = targetWindow
        // makeKeyAndOrderFront triggers windowDidBecomeKey, which updates keyModel
        // and schedules the session save, so no explicit calls are needed here.
        targetWindow.makeKeyAndOrderFront(nil)
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

    /// Saves the current set of open documents as the session. Dirty documents
    /// are snapshotted before any `await` so the RecoveryBuffer and session JSON
    /// stay consistent even if the main actor processes other work between
    /// suspensions.
    func saveSession() async {
        let snapshot = controllers.compactMap { controller -> TabSnapshot? in
            guard let tab = controller.model.tabStore.tabs.first else { return nil }
            let identity = tab.id.uuidString
            let textSystem = controller.editorStore.existingSystem(for: identity)
            let selectedRange = textSystem?.selectedRange
            let cursorPosition = selectedRange?.location
            let selectionLength = selectedRange?.length
            let scrollOffset = textSystem.map { Double($0.scrollOffset) }

            return TabSnapshot(
                record: TabRecord(
                    id: tab.id,
                    fileURL: tab.document.fileURL,
                    untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                    isPinned: tab.isPinned,
                    cursorPosition: cursorPosition,
                    selectionLength: selectionLength,
                    scrollOffset: scrollOffset
                ),
                documentID: tab.document.id,
                documentText: tab.document.text,
                documentState: tab.document.state
            )
        }

        // Capture the active tab while the snapshot is still consistent.
        // Reading this after the `await` loop would race against tab switches.
        let activeID = controllers.first { $0.window?.isKeyWindow ?? false }?.model.tabStore.activeTabID

        // Per-window `TabStore` instances also write dirty text to the recovery
        // buffer on a 300 ms debounce. We rewrite the snapshot text here so dirty
        // content captured at this point in time is persisted even if the per-window
        // debounced saves have not fired yet (e.g., on immediate app termination).
        for entry in snapshot where entry.documentState == .dirty || entry.documentState == .conflict {
            try? await recoveryBuffer.save(content: entry.documentText, for: entry.documentID)
        }

        sessionStore.saveSession(WorkspaceSession(tabs: snapshot.map(\.record), activeTabID: activeID))
    }

    /// Restores the saved session once, creating one window per document and
    /// grouping them as tabs in a single native tab group.
    func restoreSessionIfNeeded() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true

        let tempStore = TabStore(sessionStore: sessionStore)
        await tempStore.restoreSessionIfNeeded()

        if tempStore.tabs.isEmpty {
            newDocument()
            return
        }

        var firstController: WindowController?
        var firstWindow: NSWindow?

        for tab in tempStore.tabs {
            let model = makeWindowModel()
            model.tabStore.newTab(id: tab.id, document: tab.document)

            let controller = WindowController(model: model, coordinator: self)
            controllers.append(controller)

            // The text system was already created by WindowController.init; apply
            // the restored selection and scroll position before the view appears.
            let identity = tab.id.uuidString
            if let textSystem = controller.editorStore.existingSystem(for: identity) {
                if let cursorPosition = tab.cursorPosition {
                    let length = tab.selectionLength ?? 0
                    textSystem.selectedRange = NSRange(location: cursorPosition, length: length)
                }
                if let scrollOffset = tab.scrollOffset {
                    textSystem.scrollOffset = CGFloat(scrollOffset)
                }
            }

            if firstController == nil {
                firstController = controller
                firstWindow = controller.window
                controller.showWindow(nil)
            } else if let firstWindow, let newWindow = controller.window {
                firstWindow.addTabbedWindow(newWindow, ordered: .above)
                controller.showWindow(nil)
            }
        }

        let activeController: WindowController? = {
            if let activeID = tempStore.activeTabID {
                return controllers.first { $0.model.tabStore.activeTabID == activeID }
            }
            return nil
        }()
        let windowToActivate = (activeController ?? firstController)?.window
        if let windowToActivate {
            // Set the tab group's selection explicitly. Under native tabbing,
            // makeKeyAndOrderFront alone is not enough: the last-shown window
            // remains the tab group's selectedWindow and re-emerges as key on the
            // next run loop, overwriting the restored active tab.
            windowToActivate.tabGroup?.selectedWindow = windowToActivate
            windowToActivate.makeKeyAndOrderFront(nil)
        }

        updateKeyModel()
    }

    // MARK: - Internal helpers

    func removeController(_ controller: WindowController) {
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

    private func makeWindowModel() -> WorkspaceModel {
        WorkspaceModel(
            tabStore: TabStore(sessionStore: NoOpSessionStore(), recoveryBuffer: recoveryBuffer),
            stateStore: NoOpStateStore(),
            panel: panelProvider
        )
    }

    private func controllerForDocument(url: URL) -> WindowController? {
        let standardized = url.standardizedFileURL
        return controllers.first { controller in
            controller.model.tabStore.tabs.contains {
                $0.document.fileURL?.standardizedFileURL == standardized
            }
        }
    }

    func updateKeyModel() {
        keyModel = controllers.first { $0.window == NSApp.keyWindow }?.model
    }
}

// MARK: - Session snapshot

private struct TabSnapshot {
    let record: TabRecord
    let documentID: String
    let documentText: String
    let documentState: FileDocumentState
}
