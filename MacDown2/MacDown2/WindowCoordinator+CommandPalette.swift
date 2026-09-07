import AppKit

/// The ⌘⇧P command palette (epic-14-implementation.md §17 Slice 7). Split
/// out of `WindowCoordinator.swift`'s main class body to stay under the
/// `type_body_length` lint budget, matching
/// `WindowCoordinator+SessionRestore.swift`'s same reason.
extension WindowCoordinator {
    /// Shows the command palette, or closes it if one is already open.
    ///
    /// The origin window — whatever is key *before* the palette is
    /// created — is captured once here and threaded through to every
    /// command the palette can invoke. The palette panel itself becomes
    /// the key window as soon as it is shown, so anything that resolved
    /// its target from `NSApp.keyWindow` at invocation time would silently
    /// act on the palette instead of the document window the user actually
    /// meant (post-review finding #7).
    func toggleCommandPalette() {
        if let existing = commandPalette {
            existing.close()
            return
        }

        let originWindow = NSApp.keyWindow
        let originController = controllers.first(where: { $0.window == originWindow })
        let created = CommandPalettePanel(coordinator: self, originController: originController)
        // Strong ownership lives here for exactly as long as the panel is
        // open; `commandPaletteDidClose` releases it. See
        // `CommandPalettePanel`'s doc comment for why this reference must
        // exist at all (post-review finding #6).
        commandPalette = created

        if let originWindow {
            let origin = NSPoint(
                x: originWindow.frame.midX - created.frame.width / 2,
                y: min(originWindow.frame.maxY - 120, originWindow.frame.midY + 150)
            )
            created.setFrameOrigin(origin)
        } else {
            created.center()
        }
        created.makeKeyAndOrderFront(nil)
    }

    /// Called by `CommandPalettePanel.windowWillClose`. Releases the
    /// coordinator's strong reference so a closed panel is freed rather
    /// than kept alive indefinitely, and so a later `toggleCommandPalette()`
    /// creates a fresh panel instead of finding a defunct one
    /// (post-review finding #6).
    func commandPaletteDidClose(_ panel: CommandPalettePanel) {
        guard commandPalette === panel else { return }
        commandPalette = nil
    }

    /// `true` if `controller` is still a controller this coordinator owns
    /// — i.e. its window has not been closed. Distinct from merely
    /// non-`nil`: a closed `WindowController` can still be alive in memory
    /// (something else may hold a reference to it) without being a live
    /// destination for any command (post-review finding #5).
    func isLiveController(_ controller: WindowController?) -> Bool {
        guard let controller else { return false }
        return controllers.contains { $0 === controller }
    }
}
