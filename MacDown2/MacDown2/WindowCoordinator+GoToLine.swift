import AppKit

/// Ctrl-G "Go to Line/Column" (epic-22-implementation.md §6.7, §17 Slice 2b).
/// Split out of `WindowCoordinator.swift`'s main class body, matching
/// `WindowCoordinator+CommandPalette.swift`'s same reason (SwiftLint's
/// `type_body_length` budget).
extension WindowCoordinator {
    /// Shows the Go to Line panel for the key window's active document, or
    /// closes it if one is already open. Unlike the command palette, this
    /// panel has nothing useful to do without a document to jump within, so
    /// it does not open at all when there is no live editor in the key
    /// window's active tab.
    func toggleGoToLine() {
        if let existing = goToLinePanel {
            existing.close()
            return
        }

        let originWindow = NSApp.keyWindow
        guard let originController = controllers.first(where: { $0.window == originWindow }),
              let activeTab = originController.model.tabStore.activeTab,
              originController.editorStore.existingSystem(for: activeTab.id.uuidString) != nil
        else { return }

        let created = GoToLinePanel(coordinator: self, originController: originController)
        // Strong ownership lives here for exactly as long as the panel is
        // open; `goToLinePanelDidClose` releases it. See `GoToLinePanel`'s
        // doc comment for why this reference must exist at all.
        goToLinePanel = created

        if let originWindow {
            let origin = NSPoint(
                x: originWindow.frame.midX - created.frame.width / 2,
                y: min(originWindow.frame.maxY - 120, originWindow.frame.midY + 150)
            )
            created.setFrameOrigin(origin)
        } else {
            created.center()
        }
        // Same activation dance as `toggleCommandPalette` — see that
        // method's doc comment for why `makeKeyAndOrderFront` alone is
        // insufficient and why the deferral plus identity re-check matter.
        DispatchQueue.main.async { [weak self] in
            guard let self, goToLinePanel === created else { return }
            NSApp.activate(ignoringOtherApps: true)
            created.makeKeyAndOrderFront(nil)
            created.orderFrontRegardless()
        }
    }

    /// Called by `GoToLinePanel.windowWillClose`. Releases the coordinator's
    /// strong reference so a closed panel is freed rather than kept alive
    /// indefinitely, and so a later `toggleGoToLine()` creates a fresh panel
    /// instead of finding a defunct one.
    func goToLinePanelDidClose(_ panel: GoToLinePanel) {
        guard goToLinePanel === panel else { return }
        goToLinePanel = nil
    }
}
