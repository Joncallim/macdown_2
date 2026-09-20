import AppKit

/// `newDocument()`. Split out of `WindowCoordinator.swift`'s main class body
/// to stay under the `file_length` lint budget, matching
/// `WindowCoordinator+SessionRestore.swift`'s same reason.
extension WindowCoordinator {
    /// Creates a new untitled document window. When `addAsTab` is `true` and a
    /// key window exists, the new window is added as a tab of the key window.
    /// - Parameter relativeTo: when non-`nil`, used as the tab host instead
    ///   of `NSApp.keyWindow` — the command palette passes its captured
    ///   origin window here so "New Tab" targets the window the palette was
    ///   opened from rather than the palette itself (post-review
    ///   finding #7).
    /// - Parameter initialText: when non-`nil`, seeds the new document's
    ///   text once its managed lifetime is ready — used by the first-run
    ///   welcome screen's "Open a Sample Document" action. `nil` keeps
    ///   today's plain empty-untitled-document behavior.
    func newDocument(
        addAsTab: Bool = false,
        relativeTo overrideKeyWindow: NSWindow? = nil,
        initialText: String? = nil
    ) {
        let keyWindow = overrideKeyWindow ?? NSApp.keyWindow

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
            let created = await model.newManagedDocument(encoding: encoding) {
                !Task.isCancelled && self.controllers.contains { $0 === controller }
            }
            if created, let initialText {
                model.tabStore.updateActiveDocument { $0.updatingText(initialText) }
            }
        }
    }
}
