import AppKit
import SwiftUI
import TextFilters

/// A borderless, floating panel hosting `CommandPaletteView`
/// (epic-14-implementation.md §17 Slice 7).
///
/// Ownership (post-review finding #6): `NSPanel`'s `isReleasedWhenClosed`
/// defaults to `false` — unlike many `NSWindow`s, AppKit does **not**
/// deallocate this panel on its own when it closes, so something must hold
/// a strong reference for exactly as long as the panel should exist.
/// `WindowCoordinator` is that owner (`commandPalette` in
/// `WindowCoordinator+CommandPalette.swift`); this panel is its own
/// delegate purely to notify the coordinator when it closes
/// (`commandPaletteDidClose`), so that strong reference is released and a
/// closed panel is never mistaken for a reusable, still-open one. The panel
/// holds only a `weak` reference back to the coordinator, so there is no
/// retain cycle: coordinator → panel is the only strong edge.
@MainActor
final class CommandPalettePanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?

    convenience init(
        coordinator: WindowCoordinator,
        originController: WindowController?,
        appCommands: [AppPaletteCommand] = AppPaletteCommand.standard,
        discoverTextFilters: @escaping () -> [TextFilterCommand] = { TextFilterCommandDiscovery.discoverCommands() }
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.coordinator = coordinator
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        delegate = self

        let model = CommandPaletteModel(
            appCommands: appCommands,
            discoverTextFilters: discoverTextFilters,
            isAppCommandAvailable: { [weak coordinator] command in
                guard let coordinator else { return false }
                return command.isAvailable(coordinator, originController)
            },
            textFiltersAvailable: originController.map {
                coordinator.textFilterCoordinator.editingTarget(for: $0) != nil
            } ?? false
        )
        let view = CommandPaletteView(
            model: model,
            coordinator: coordinator,
            originController: originController,
            onDismiss: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: view)
    }

    func windowWillClose(_: Notification) {
        coordinator?.commandPaletteDidClose(self)
    }
}
