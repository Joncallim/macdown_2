import AppKit
import SwiftUI
import TextSearch

/// A borderless, floating panel hosting `QuickOpenView` (EPIC-22 §6.15,
/// Slice 6b) — Cmd-P fuzzy file navigation for the active folder root.
///
/// Ownership mirrors `CommandPalettePanel` exactly, per §6.15's own explicit
/// decision to reuse that idiom rather than `GoToLinePanel`'s: `NSPanel`'s
/// `isReleasedWhenClosed` defaults to `false`, so `WindowCoordinator`
/// (`quickOpen` in `WindowCoordinator+QuickOpen.swift`) holds this panel
/// strongly for exactly as long as it is open, releasing it via
/// `quickOpenDidClose` when `windowWillClose` fires. Only a `weak` reference
/// back to the coordinator, so there is no retain cycle.
@MainActor
final class QuickOpenPanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?
    /// The window this panel was opened from, so `WindowCoordinator` can
    /// close it the instant that window closes rather than leaving it open
    /// against an already-evicted `fileTreeModel`/`workspaceFileIndex` —
    /// same reasoning as `CommandPalettePanel.originController` and
    /// `GoToLinePanel.originController`.
    private(set) weak var originController: WindowController?

    convenience init(
        coordinator: WindowCoordinator,
        originController: WindowController,
        index: WorkspaceFileIndex
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.coordinator = coordinator
        self.originController = originController
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        delegate = self

        let model = QuickOpenModel(index: index)
        let view = QuickOpenView(
            model: model,
            onOpen: { [weak coordinator, weak originController] path in
                // Resolved against the origin's own live root, not a value
                // captured once at panel-open time — the same "read live
                // state at the moment of the action, not a stale snapshot"
                // discipline `CommandPaletteView`'s filter handler already
                // established for the identical reason (post-review finding
                // #7 on that slice). This is a REAL requirement here, not
                // just defensive style: an independent hostile review of
                // this slice found the origin window's root CAN change
                // while this panel stays open (Open Folder…/Open Recent
                // Folder/session restore all switch an already-open
                // window's root without closing it) — fixed by having
                // `WindowController.setFileTreeRoot` close this panel via
                // `WindowCoordinator.closeQuickOpenIfOrigin` whenever that
                // happens, so this guard should never actually observe a
                // root that moved out from under it, but resolving live
                // rather than from a captured value is the correct,
                // consistent choice regardless.
                guard let coordinator, let originController,
                      let root = originController.fileTreeModel.rootAccessURL
                else { return }
                let url = root.appendingPathComponent(path.relativePath)
                Task {
                    // `relativeTo: originController.window`, not
                    // `NSApp.keyWindow` — this panel itself is the key
                    // window while it is on screen, exactly the mistake
                    // `CommandPalettePanel`'s own origin-capture idiom
                    // exists to avoid (post-review finding #7 there).
                    await coordinator.openDocument(at: url, relativeTo: originController.window)
                }
            },
            onDismiss: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: view)
    }

    func windowWillClose(_: Notification) {
        coordinator?.quickOpenDidClose(self)
    }
}
