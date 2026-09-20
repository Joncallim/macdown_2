import AppKit

/// The first-run welcome window (E15 deliverable 6: "final first-run/sample/
/// onboarding UI"). Split out of `WindowCoordinator.swift`'s main class body,
/// matching `WindowCoordinator+CommandPalette.swift`'s same reason.
extension WindowCoordinator {
    /// Shows the first-run welcome window. `onDismiss` runs exactly once,
    /// however the window closes (an explicit choice or the window's own
    /// close button), so the caller can proceed with normal launch exactly
    /// once regardless of which path the user took.
    func showFirstRunWindow(onDismiss: @escaping () -> Void) {
        guard firstRunWindow == nil else { return }
        var didDismiss = false
        let dismissOnce = { [weak self] in
            guard !didDismiss else { return }
            didDismiss = true
            self?.firstRunWindow = nil
            onDismiss()
        }
        let created = FirstRunWindowController(
            onStartWriting: { [weak self] in
                self?.newDocument()
                dismissOnce()
            },
            onOpenSample: { [weak self] in
                self?.newDocument(initialText: FirstRunSampleDocument.text)
                dismissOnce()
            },
            onClose: dismissOnce
        )
        // Strong ownership lives here for exactly as long as the window is
        // open, for the same reason `commandPalette` does — see
        // `WindowCoordinator+CommandPalette.swift`.
        firstRunWindow = created
        created.showWindow(nil)
        created.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        created.window?.makeKeyAndOrderFront(nil)
    }
}
