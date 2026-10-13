import AppKit

/// The first-run welcome window (E15 deliverable 6: "final first-run/sample/
/// onboarding UI"). Split out of `WindowCoordinator.swift`'s main class body,
/// matching `WindowCoordinator+CommandPalette.swift`'s same reason.
extension WindowCoordinator {
    /// Shows the first-run welcome window. `onDismiss` runs exactly once,
    /// however the window closes (an explicit choice or the window's own
    /// close button), so the caller can proceed with normal launch exactly
    /// once regardless of which path the user took. Its argument is `true`
    /// when the choice itself already opened a document ("Start Writing" or
    /// "Open a Sample Document"), so the caller's normal launch must not
    /// also fall back to opening its own untitled document — doing so left a
    /// second, empty "Untitled" tab in front of the sample (found by the
    /// first real run of `FirstRunUITests`).
    func showFirstRunWindow(onDismiss: @escaping (_ openedDocument: Bool) -> Void) {
        guard firstRunWindow == nil else { return }
        var didDismiss = false
        let dismissOnce = { [weak self] (openedDocument: Bool) in
            guard !didDismiss else { return }
            didDismiss = true
            self?.firstRunWindow = nil
            onDismiss(openedDocument)
        }
        let created = FirstRunWindowController(
            onStartWriting: { [weak self] in
                self?.newDocument()
                dismissOnce(true)
            },
            onOpenSample: { [weak self] in
                self?.newDocument(initialText: FirstRunSampleDocument.text)
                dismissOnce(true)
            },
            onClose: { dismissOnce(false) }
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
