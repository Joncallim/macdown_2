import AppKit
import SwiftUI

/// A borderless, floating panel hosting `CommandPaletteView`
/// (epic-14-implementation.md §17 Slice 7). One instance is created per
/// invocation and closes (and, by AppKit's default `isReleasedWhenClosed`,
/// deallocates) itself — there is no persistent palette window to manage
/// state for between openings.
@MainActor
final class CommandPalettePanel: NSPanel {
    convenience init(coordinator: WindowCoordinator, onDismiss: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating

        let model = CommandPaletteModel()
        let view = CommandPaletteView(model: model, coordinator: coordinator, onDismiss: onDismiss)
        contentView = NSHostingView(rootView: view)
    }
}
