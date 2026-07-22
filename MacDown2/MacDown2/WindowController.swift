import AppKit
import EditorCore
import FileCore
import Foundation
import Highlighting
import SwiftUI
import Themes
import Workspace

/// A single document window. Each window is also a tab when grouped by the
/// native tab bar.
@MainActor
final class WindowController: NSWindowController, NSWindowDelegate {
    let model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let highlightStore: SyntaxHighlightStore
    let themeController: ThemeController
    private weak var coordinator: WindowCoordinator?
    private var observationTask: Task<Void, Never>?
    private var lastObservedTitle: String = ""
    private var lastObservedDirty: Bool = false
    private var lastObservedLanguageID: String?

    init(
        model: WorkspaceModel,
        coordinator: WindowCoordinator,
        themeController: ThemeController,
        grammarRegistry: GrammarRegistry
    ) {
        self.model = model
        self.coordinator = coordinator
        self.themeController = themeController
        editorStore = EditorTextSystemStore()
        highlightStore = SyntaxHighlightStore(registry: grammarRegistry)

        // Eagerly create the text system for the active tab so session-save
        // can read cursor/scroll state even before SwiftUI mounts the view.
        if let activeTab = model.tabStore.activeTab {
            _ = editorStore.system(
                for: activeTab.id.uuidString,
                initialText: activeTab.document.text,
                configuration: .default
            )
        }

        let hostingController = NSHostingController(rootView: WorkspaceShellView(
            model: model,
            editorStore: editorStore,
            highlightStore: highlightStore,
            themeController: themeController
        ))
        let window = NSWindow(contentViewController: hostingController)
        window.setFrameAutosaveName("MacDown2DocumentWindow")
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

    deinit {
        observationTask?.cancel()
    }

    private func startObservingActiveDocument() {
        // Polling is used instead of `withObservationTracking` because the
        // observation closure in the previous implementation leaked the task.
        // The 250 ms period is a pragmatic trade-off: title/dirty changes may
        // take up to one tick to reflect, but session saves are coalesced.
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                updateTitleAndEditedState()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func updateTitleAndEditedState() {
        let document = model.activeDocument
        let baseTitle = document?.fileURL?.lastPathComponent ?? "Untitled"
        let isDirty = document?.state == .dirty || document?.state == .conflict
        let title = isDirty ? "● \(baseTitle)" : baseTitle

        window?.title = title
        window?.representedURL = document?.fileURL
        window?.isDocumentEdited = isDirty

        let changed = title != lastObservedTitle || isDirty != lastObservedDirty
        lastObservedTitle = title
        lastObservedDirty = isDirty
        if changed {
            coordinator?.scheduleSaveSession()
        }

        // Re-attach the highlighter if the active document's format changed
        // (e.g., after Save As). The `highlighter(for:)` method on
        // `SyntaxHighlightStore` detects the language mismatch and calls
        // `setLanguage` automatically.
        let currentLanguageID = document?.format.highlightLanguageID
        if lastObservedLanguageID != currentLanguageID {
            lastObservedLanguageID = currentLanguageID
            guard let activeTab = model.tabStore.activeTab,
                  let textSystem = editorStore.existingSystem(for: activeTab.id.uuidString)
            else {
                return
            }
            _ = highlightStore.highlighter(
                for: activeTab.id.uuidString,
                textSystem: textSystem,
                languageID: currentLanguageID,
                theme: themeController.current
            )
        }
    }

    func windowWillClose(_: Notification) {
        observationTask?.cancel()
        editorStore.evictAll()
        highlightStore.evictAll()
    }

    func windowDidBecomeKey(_: Notification) {
        // Called by AppKit when this window (or tab) becomes key. This is the
        // deterministic hook for native tab switches, and it only fires for
        // document windows because the coordinator is their delegate.
        coordinator?.updateKeyModel()
        coordinator?.scheduleSaveSession()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator, coordinator.controllers.contains(where: { $0 === self }) else { return true }

        guard let document = model.activeDocument, document.state != .clean else {
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
                // Keep a strong reference to the parent window so we can restore
                // key focus after dismissing the sheet.
                let parentWindow = sender

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
                    // Ensure this window remains key. AppKit can switch the tab-
                    // group selection during sheet dismissal under native tabbing.
                    parentWindow.makeKeyAndOrderFront(nil)
                }
            }
        }

        return false
    }
}
