import AppKit
import FileCore
import Foundation
import Observation
import SwiftUI
import Workspace

extension EnvironmentValues {
    @Entry var windowCoordinator: WindowCoordinator?
}

// MARK: - In-memory stores for per-window models

/// A no-op session store so per-window `TabStore` instances do not compete with
/// the global coordinator when saving the session.
@MainActor
final class NoOpSessionStore: WorkspaceSessionStoring {
    func loadSession() -> WorkspaceSession? {
        nil
    }

    func saveSession(_: WorkspaceSession) {}
}

/// A no-op state store so sidebar state is independent per window.
@MainActor
final class NoOpStateStore: WorkspaceStateStoring {
    var sidebarVisible: Bool = true
    var sidebarSectionExpanded: [String: Bool] = [:]
}

// MARK: - Coordinator

/// Owns the global document pool and the native `NSWindow` controllers that
/// present each document as a tab.
@MainActor
@Observable
final class WindowCoordinator {
    /// The model for the document currently shown in the key window.
    private(set) var keyModel: WorkspaceModel?

    fileprivate var controllers: [WindowController] = []
    private let sessionStore: WorkspaceSessionStoring
    private let panelProvider: NSFilePanelProvider
    private var hasRestoredSession = false

    init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        panelProvider: NSFilePanelProvider = NSFilePanelProvider()
    ) {
        self.sessionStore = sessionStore
        self.panelProvider = panelProvider
        subscribeToKeyWindowChanges()
    }

    // MARK: - Window lifecycle

    /// Creates a new untitled document window. When `addAsTab` is `true` and a
    /// key window exists, the new window is added as a tab of the key window.
    func newDocument(addAsTab: Bool = false) {
        let model = makeWindowModel()
        model.newDocument()
        let controller = WindowController(model: model, coordinator: self)
        addController(controller, addingAsTab: addAsTab)
    }

    /// Opens a file in a new window, or activates the existing window if the
    /// same file is already open.
    func openDocument(at url: URL) async {
        if let existing = controllerForDocument(url: url) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let model = makeWindowModel()
        _ = await model.tabStore.openFileInTab(url)

        guard !model.tabStore.tabs.isEmpty else { return }
        let controller = WindowController(model: model, coordinator: self)
        addController(controller, addingAsTab: true)
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
        NSApp.keyWindow?.performClose(nil)
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
        tabGroup.windows[targetIndex].makeKeyAndOrderFront(nil)
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

    /// Saves the current set of open documents as the session.
    func saveSession() async {
        for controller in controllers {
            guard let tab = controller.model.tabStore.tabs.first,
                  tab.document.state == .dirty || tab.document.state == .conflict
            else { continue }
            try? await RecoveryBuffer.shared.save(content: tab.document.text, for: tab.document.id)
        }

        let records = controllers.compactMap { controller -> TabRecord? in
            guard let tab = controller.model.tabStore.tabs.first else { return nil }
            return TabRecord(
                id: tab.id,
                fileURL: tab.document.fileURL,
                untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                isPinned: tab.isPinned,
                cursorPosition: nil,
                scrollOffset: nil
            )
        }

        let activeID = controllers.first { $0.window?.isKeyWindow ?? false }?.model.tabStore.activeTabID
        sessionStore.saveSession(WorkspaceSession(tabs: records, activeTabID: activeID))
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
        for tab in tempStore.tabs {
            let model = makeWindowModel()
            model.tabStore.newTab()
            model.tabStore.updateActiveDocument { _ in tab.document }

            let controller = WindowController(model: model, coordinator: self)
            controllers.append(controller)

            if firstController == nil {
                firstController = controller
            } else if let firstWindow = firstController?.window, let newWindow = controller.window {
                firstWindow.addTabbedWindow(newWindow, ordered: .above)
            }
        }

        for controller in controllers {
            controller.showWindow(nil)
        }

        let activeController: WindowController? = {
            if let activeID = tempStore.activeTabID {
                return controllers.first { $0.model.tabStore.activeTabID == activeID }
            }
            return nil
        }()
        if let activeController {
            activeController.window?.makeKeyAndOrderFront(nil)
        } else {
            firstController?.window?.makeKeyAndOrderFront(nil)
        }

        updateKeyModel()
    }

    // MARK: - Internal helpers

    func removeController(_ controller: WindowController) {
        controllers.removeAll { $0 === controller }
        updateKeyModel()
    }

    private func addController(_ controller: WindowController, addingAsTab: Bool) {
        controllers.append(controller)

        let keyWindow = NSApp.keyWindow
        let newWindow = controller.window
        if addingAsTab, let key = keyWindow, key != controller.window, let tab = newWindow {
            key.addTabbedWindow(tab, ordered: .above)
        }

        controller.showWindow(nil)
        updateKeyModel()
    }

    private func makeWindowModel() -> WorkspaceModel {
        WorkspaceModel(
            tabStore: TabStore(sessionStore: NoOpSessionStore()),
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

    private func subscribeToKeyWindowChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateKeyModel),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc
    private func updateKeyModel() {
        keyModel = controllers.first { $0.window == NSApp.keyWindow }?.model
    }
}

// MARK: - Window controller

/// A single document window. Each window is also a tab when grouped by the
/// native tab bar.
@MainActor
final class WindowController: NSWindowController, NSWindowDelegate {
    let model: WorkspaceModel
    private weak var coordinator: WindowCoordinator?

    init(model: WorkspaceModel, coordinator: WindowCoordinator) {
        self.model = model
        self.coordinator = coordinator

        let hostingController = NSHostingController(rootView: WorkspaceShellView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = model.activeDocument?.fileURL?.lastPathComponent ?? "Untitled"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .preferred

        super.init(window: window)
        window.delegate = self
        updateTitleAndEditedState()
        startObservingActiveDocument()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func startObservingActiveDocument() {
        Task { @MainActor [weak self] in
            while let self {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.model.activeDocument
                    } onChange: {
                        continuation.resume()
                    }
                }
                updateTitleAndEditedState()
            }
        }
    }

    private func updateTitleAndEditedState() {
        let document = model.activeDocument
        let baseTitle = document?.fileURL?.lastPathComponent ?? "Untitled"
        let isDirty = document?.state == .dirty || document?.state == .conflict
        window?.title = isDirty ? "● \(baseTitle)" : baseTitle
        window?.representedURL = document?.fileURL
        window?.isDocumentEdited = isDirty
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator, coordinator.controllers.contains(where: { $0 === self }) else { return true }

        guard let document = model.activeDocument, document.state != .clean else {
            Task { await coordinator.saveSession() }
            coordinator.removeController(self)
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        let fileName = document.fileURL?.lastPathComponent ?? "Untitled"
        alert.informativeText = "Do you want to save changes to \"\(fileName)\"?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: sender) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, let coordinator = self.coordinator else { return }

                switch response {
                case .alertFirstButtonReturn:
                    await model.save()
                    if model.activeDocument?.state == .clean {
                        coordinator.removeController(self)
                        close()
                    }
                case .alertThirdButtonReturn:
                    await model.tabStore.resolveClose(.discard)
                    coordinator.removeController(self)
                    close()
                default:
                    break
                }
            }
        }

        return false
    }
}
