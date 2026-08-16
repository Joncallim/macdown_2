import AppKit
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
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
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let fileTreeModel: FileTreeModel
    let externalFileController: ExternalFileController
    weak var coordinator: WindowCoordinator?
    private var observationTask: Task<Void, Never>?
    private var lastObservedTitle: String = ""
    private var lastObservedDirty: Bool = false
    private var lastObservedURL: URL?
    private var lastObservedLanguageID: String?

    init(
        model: WorkspaceModel,
        coordinator: WindowCoordinator,
        themeController: ThemeController,
        grammarRegistry: GrammarRegistry,
        fileTreePreferences: FileTreePreferences,
        recoveryExecutor: any RecoveryActionExecuting = DefaultRecoveryActionExecutor()
    ) {
        self.model = model
        self.coordinator = coordinator
        self.themeController = themeController
        editorStore = EditorTextSystemStore()
        highlightStore = SyntaxHighlightStore(registry: grammarRegistry)
        // 100 ms debounce + ≤50 ms parse/slice/render pipeline = the 150 ms
        // keystroke-to-preview budget (plan D8). The package default stays at
        // 150 ms so other consumers of `MarkdownParseStore` keep the
        // conservative, E06-tested value; this is the one call site that
        // opts into the tighter production budget.
        parseStore = MarkdownParseStore(debounce: .milliseconds(100))
        jsonAnalysisStore = JSONAnalysisStore(debounce: .milliseconds(100))
        outlineController = OutlineController()
        fileTreeModel = Self.makeFileTreeModel(preferences: fileTreePreferences)
        externalFileController = Self.makeExternalFileController(
            model: model,
            editorStore: editorStore,
            coordinator: coordinator,
            recoveryExecutor: recoveryExecutor
        )

        // Eagerly create the text system and parse session for the active tab
        // so session-save can read cursor/scroll state and the preview can
        // render immediately once SwiftUI mounts the view.
        let shell = WorkspaceShellView(
            model: model,
            editorStore: editorStore,
            highlightStore: highlightStore,
            parseStore: parseStore,
            jsonAnalysisStore: jsonAnalysisStore,
            themeController: themeController,
            outlineController: outlineController,
            fileTreeModel: fileTreeModel,
            externalFileController: externalFileController
        )
        .environment(\.windowCoordinator, coordinator)
        let hostingController = NSHostingController(rootView: shell)
        let window = DocumentWindow(contentViewController: hostingController)
        window.coordinator = coordinator
        window.setFrameAutosaveName("MacDown2DocumentWindow")
        window.title = model.activeDocument?.fileURL?.lastPathComponent ?? "Untitled"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .preferred

        super.init(window: window)
        makeSessionsForActiveTab()
        externalFileController.attach(owner: self)
        window.delegate = self
        fileTreeModel.startObservingPreferences()
        updateTitleAndEditedState()
        startObservingActiveDocument()
        externalFileController.start()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Eagerly creates the text system and both analysis sessions for the
    /// active tab so session-save can read cursor/scroll state and the preview
    /// can render immediately once SwiftUI mounts the view.
    private func makeSessionsForActiveTab() {
        guard let activeTab = model.tabStore.activeTab else { return }
        let identity = activeTab.id.uuidString
        _ = editorStore.system(
            for: identity,
            initialText: activeTab.document.text,
            configuration: .default
        )
        _ = parseStore.session(for: identity)
        _ = jsonAnalysisStore.session(for: identity)
    }

    private static func makeExternalFileController(
        model: WorkspaceModel,
        editorStore: EditorTextSystemStore,
        coordinator: WindowCoordinator,
        recoveryExecutor: any RecoveryActionExecuting
    ) -> ExternalFileController {
        ExternalFileController(
            model: model,
            editorStore: editorStore,
            identity: model.tabStore.activeTab?.id.uuidString ?? UUID().uuidString,
            coordinator: coordinator,
            recoveryExecutor: recoveryExecutor
        )
    }

    private static func makeFileTreeModel(preferences: FileTreePreferences) -> FileTreeModel {
        FileTreeModel(
            preferences: preferences,
            supportedExtensions: Set(FileFormatRegistry.defaultFormats.flatMap(\.extensions))
        )
    }

    deinit {
        observationTask?.cancel()
        let controller = externalFileController
        Task { @MainActor in
            controller.dispose()
        }
    }

    private func startObservingActiveDocument() {
        // Polling is used instead of `withObservationTracking` because the
        // observation closure in the previous implementation leaked the task.
        // Keep the active native tab responsive, but do not wake every hidden
        // tab four times a second solely to re-check its title.
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                updateTitleAndEditedState()
                let interval: Duration = window?.isKeyWindow == true ? .milliseconds(250) : .seconds(1)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func updateTitleAndEditedState() {
        let document = model.activeDocument
        let baseTitle = document?.fileURL?.lastPathComponent ?? "Untitled"
        let isDirty = document?.state == .dirty || document?.state == .conflict
        let title = isDirty ? "● \(baseTitle)" : baseTitle
        let url = document?.fileURL

        let changed = title != lastObservedTitle || isDirty != lastObservedDirty || url != lastObservedURL
        lastObservedTitle = title
        lastObservedDirty = isDirty
        lastObservedURL = url
        if changed {
            window?.title = title
            window?.representedURL = url
            window?.isDocumentEdited = isDirty
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
        externalFileController.dispose()
        editorStore.evictAll()
        highlightStore.evictAll()
        parseStore.evictAll()
        jsonAnalysisStore.evictAll()
        fileTreeModel.dispose()
    }

    func windowDidBecomeKey(_: Notification) {
        // Called by AppKit when this window (or tab) becomes key. This is the
        // deterministic hook for native tab switches, and it only fires for
        // document windows because the coordinator is their delegate.
        coordinator?.updateKeyModel()
        coordinator?.scheduleSaveSession()
        // The inactive polling cadence is intentionally low; refresh once
        // synchronously when a native tab becomes visible again.
        updateTitleAndEditedState()
        externalFileController.retryMonitoring()
        Task { await fileTreeModel.rescanExpandedDirectories() }
    }

    func saveDocument() async {
        await model.save()
        externalFileController.synchronize(with: model.activeDocument)
        updateTitleAndEditedState()
    }

    func saveDocumentAs() async {
        await externalFileController.drainRecovery()
        await model.saveAs()
        externalFileController.synchronize(with: model.activeDocument)
        updateTitleAndEditedState()
    }
}
