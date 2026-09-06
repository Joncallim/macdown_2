import AppKit
import TextFilters

/// One app command the command palette can invoke, distinct from a
/// discovered text filter (epic-14-implementation.md §5, §17 Slice 7). A
/// small, explicit, hand-maintained array — not generated from
/// `WorkspaceCommands` — per that section's accepted drift-risk tradeoff at
/// this list's current size. `@MainActor` because `action` manipulates the
/// (also `@MainActor`) `WindowCoordinator`.
@MainActor
struct AppPaletteCommand: Identifiable {
    let id: String
    let title: String
    let action: (WindowCoordinator) -> Void
}

extension AppPaletteCommand {
    static let standard: [AppPaletteCommand] = [
        AppPaletteCommand(id: "newFile", title: "New File") { $0.newDocument(addAsTab: true) },
        AppPaletteCommand(id: "newTab", title: "New Tab") { $0.newDocument(addAsTab: true) },
        AppPaletteCommand(id: "open", title: "Open…") { $0.openFile() },
        AppPaletteCommand(id: "openFolder", title: "Open Folder…") { $0.chooseFolder() },
        AppPaletteCommand(id: "save", title: "Save") { $0.saveKeyDocument() },
        AppPaletteCommand(id: "saveAs", title: "Save As…") { $0.saveKeyDocumentAs() },
        AppPaletteCommand(id: "closeTab", title: "Close Tab") { $0.closeKeyWindow() },
        AppPaletteCommand(id: "export", title: "Export…") { coordinator in
            Task { await coordinator.exportCoordinator.exportActiveDocument() }
        },
        AppPaletteCommand(id: "toggleSidebar", title: "Toggle Sidebar") { $0.keyModel?.sidebarVisible.toggle() },
        AppPaletteCommand(id: "showCommandsFolder", title: "Show Commands Folder") { _ in
            let directory = TextFilterCommandDiscovery.commandsDirectory
            _ = TextFilterCommandDiscovery.discoverCommands(in: directory)
            NSWorkspace.shared.open(directory)
        },
    ]
}
