import AppKit
import TextFilters

/// One app command the command palette can invoke, distinct from a
/// discovered text filter (epic-14-implementation.md §5, §17 Slice 7). A
/// small, explicit, hand-maintained array — not generated from
/// `WorkspaceCommands` — per that section's accepted drift-risk tradeoff at
/// this list's current size. `@MainActor` because `action` manipulates the
/// (also `@MainActor`) `WindowCoordinator`.
///
/// `action`/`isAvailable` both take the palette's captured origin
/// `WindowController` (`nil` if the palette was opened with no document
/// window, or the origin has since closed) rather than resolving
/// `NSApp.keyWindow` themselves — the palette panel *is* the key window
/// while these run, so a command that resolved its own target internally
/// would silently act on the palette instead of the originating document
/// (post-review finding #7).
@MainActor
struct AppPaletteCommand: Identifiable {
    let id: String
    let title: String
    let isAvailable: (WindowCoordinator, WindowController?) -> Bool
    let action: (WindowCoordinator, WindowController?) -> Void

    init(
        id: String,
        title: String,
        isAvailable: @escaping (WindowCoordinator, WindowController?) -> Bool = { _, _ in true },
        action: @escaping (WindowCoordinator, WindowController?) -> Void
    ) {
        self.id = id
        self.title = title
        self.isAvailable = isAvailable
        self.action = action
    }
}

extension AppPaletteCommand {
    static let standard: [AppPaletteCommand] = [
        AppPaletteCommand(
            id: "newFile",
            title: "New File",
            // Mirrors `WorkspaceCommands`' real "New File" menu item: only
            // meaningful with an open folder (post-review finding #8 — the
            // palette previously aliased this to "New Tab", which drifted
            // from the real command it claimed to mirror in the same PR
            // that introduced it).
            isAvailable: { _, controller in controller?.fileTreeModel.root != nil },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.createInFolder(isDirectory: false, controller: controller)
            }
        ),
        AppPaletteCommand(id: "newTab", title: "New Tab") { coordinator, controller in
            coordinator.newDocument(addAsTab: true, relativeTo: controller?.window)
        },
        // `relativeTo`/`in`: explicit target, not `NSApp.keyWindow` (which
        // is the palette itself while these run) — post-review finding #4.
        AppPaletteCommand(id: "open", title: "Open…") { coordinator, controller in
            coordinator.openFile(relativeTo: controller)
        },
        AppPaletteCommand(id: "openFolder", title: "Open Folder…") { coordinator, controller in
            coordinator.chooseFolder(relativeTo: controller)
        },
        AppPaletteCommand(
            id: "save",
            title: "Save",
            isAvailable: { _, controller in controller?.model.canSave == true },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.saveDocument(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "saveAs",
            title: "Save As…",
            isAvailable: { _, controller in controller?.model.hasActiveDocument == true },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.saveDocumentAs(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "closeTab",
            title: "Close Tab",
            isAvailable: { _, controller in controller?.model.canClose == true },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.closeTab(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "toggleSidebar",
            title: "Toggle Sidebar",
            // Unlike the other commands above, toggling the sidebar has no
            // other precondition of its own to fall back on — without this,
            // it would stay "available" (and invocable) against an origin
            // whose window has already closed (post-review finding #5).
            isAvailable: { coordinator, controller in coordinator.isLiveController(controller) },
            action: { _, controller in controller?.model.sidebarVisible.toggle() }
        ),
        AppPaletteCommand(id: "showCommandsFolder", title: "Show Commands Folder") { _, _ in
            let directory = TextFilterCommandDiscovery.commandsDirectory
            _ = TextFilterCommandDiscovery.discoverCommands(in: directory)
            NSWorkspace.shared.open(directory)
        },
    ]
}
