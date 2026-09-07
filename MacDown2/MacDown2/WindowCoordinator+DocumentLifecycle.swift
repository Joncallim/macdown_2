import AppKit

/// Close/Save/Save As, in both their real-menu ("key window") and
/// explicit-target forms. Split out of `WindowCoordinator.swift`'s main
/// class body to stay under the `type_body_length`/`file_length` lint
/// budgets, matching `WindowCoordinator+SessionRestore.swift`'s same
/// reason.
///
/// The explicit-target variants exist for the command palette
/// (post-review finding #7 on the E14B remediation): the palette panel
/// itself is `NSApp.keyWindow` while these run, so a command that resolved
/// its own target from `NSApp.keyWindow` at invocation time would silently
/// act on the palette instead of the document window the user actually
/// meant. The real menu commands are unchanged thin wrappers that resolve
/// the key window once and delegate to the same body.
extension WindowCoordinator {
    /// Closes the tab/window that is currently key.
    func closeKeyWindow() {
        guard let controller = controllers.first(where: { $0.window?.isKeyWindow ?? false }) else { return }
        closeTab(in: controller)
    }

    func closeTab(in controller: WindowController) {
        guard let window = controller.window else { return }
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
        saveDocument(in: controller)
    }

    func saveKeyDocumentAs() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        saveDocumentAs(in: controller)
    }

    func saveDocument(in controller: WindowController) {
        Task { await controller.saveDocument() }
    }

    func saveDocumentAs(in controller: WindowController) {
        Task { await controller.saveDocumentAs() }
    }
}
