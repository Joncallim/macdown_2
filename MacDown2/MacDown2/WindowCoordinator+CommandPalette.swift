import AppKit

/// The ⌘⇧P command palette (epic-14-implementation.md §17 Slice 7). Split
/// out of `WindowCoordinator.swift`'s main class body to stay under the
/// `type_body_length` lint budget, matching
/// `WindowCoordinator+SessionRestore.swift`'s same reason.
///
/// No stored panel reference is needed: at most one palette is ever open at
/// a time, found by scanning `NSApp.windows` for an existing
/// `CommandPalettePanel` rather than tracked as coordinator state.
extension WindowCoordinator {
    /// Shows the command palette, or closes it if one is already open.
    func toggleCommandPalette() {
        if let existing = NSApp.windows.first(where: { $0 is CommandPalettePanel }) as? CommandPalettePanel {
            existing.close()
            return
        }

        var panel: CommandPalettePanel?
        let created = CommandPalettePanel(coordinator: self) { panel?.close() }
        panel = created

        if let keyWindow = NSApp.keyWindow {
            let origin = NSPoint(
                x: keyWindow.frame.midX - created.frame.width / 2,
                y: min(keyWindow.frame.maxY - 120, keyWindow.frame.midY + 150)
            )
            created.setFrameOrigin(origin)
        } else {
            created.center()
        }
        created.makeKeyAndOrderFront(nil)
    }
}
