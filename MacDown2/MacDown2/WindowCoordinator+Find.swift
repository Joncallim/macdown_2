import AppKit

/// Current-document Find bar toggle (EPIC-22 §6.14, Slice 5a). Split out of
/// `WindowCoordinator.swift`'s main class body, matching
/// `WindowCoordinator+GoToLine.swift`'s same reason (SwiftLint's
/// `type_body_length` budget).
///
/// Unlike Go to Line/Command Palette, Find is an inline bar owned by
/// `DocumentEditorSplitView`'s own per-identity `EditorFindModelStore`
/// (§6.14's explicit departure from this codebase's two existing
/// floating-panel precedents) — there is no panel for this coordinator to
/// create or track. Toggling is just flipping that model's own `isActive`.
extension WindowCoordinator {
    /// Shows the Find bar for the key window's active tab, or hides it if
    /// already showing. A no-op with no live editor in the key window's
    /// active tab, mirroring `toggleGoToLine()`'s same guard.
    func toggleFind() {
        guard let originWindow = NSApp.keyWindow,
              let originController = controllers.first(where: { $0.window == originWindow }),
              let activeTab = originController.model.tabStore.activeTab,
              originController.editorStore.existingSystem(for: activeTab.id.uuidString) != nil
        else { return }

        let identity = activeTab.id.uuidString
        let model = originController.findStore.model(for: identity)
        model.isActive.toggle()
        guard !model.isActive else { return }
        // Closing: clear highlighting immediately rather than waiting for
        // `FindBarView.onClose` to run — that closure only fires while the
        // bar's own view is still on screen to call it; toggling `isActive`
        // straight from the menu command removes the view on the very same
        // update, so nothing would otherwise call `setFindHighlights` to
        // clear the now-stale highlight ranges from the last search.
        originController.editorStore.existingSystem(for: identity)?.setFindHighlights(ranges: [], currentIndex: nil)
    }
}
