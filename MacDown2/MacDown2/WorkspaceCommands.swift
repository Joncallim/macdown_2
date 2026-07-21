import AppKit
import SwiftUI
import Workspace

struct WorkspaceCommands: Commands {
    @Environment(\.windowCoordinator) private var coordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                coordinator?.newDocument(addAsTab: false)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                coordinator?.newDocument(addAsTab: true)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Open…") {
                coordinator?.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                Task { await coordinator?.keyModel?.openFolder() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                Task { await coordinator?.keyModel?.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(coordinator?.keyModel?.canSave != true)

            Button("Save As…") {
                Task { await coordinator?.keyModel?.saveAs() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            Button("Close Tab") {
                coordinator?.closeKeyWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(coordinator?.keyModel?.canClose != true)
        }

        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") {
                coordinator?.selectNextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(coordinator?.keyWindowHasMultipleTabs != true)

            Button("Show Previous Tab") {
                coordinator?.selectPreviousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(coordinator?.keyWindowHasMultipleTabs != true)

            ForEach(1 ..< 10, id: \.self) { index in
                Button("Select Tab \(index)") {
                    coordinator?.selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                .disabled(coordinator?.keyWindowHasTab(at: index - 1) != true)
            }
        }

        CommandGroup(before: .sidebar) {
            Button("Toggle Sidebar") {
                coordinator?.keyModel?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        #if DEBUG
            CommandMenu("Debug") {
                Button("Mark Active Tab Dirty") {
                    coordinator?.keyModel?.tabStore.updateActiveDocument { $0.updatingText($0.text + " ") }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift, .option])
                .disabled(coordinator?.keyModel?.hasActiveDocument != true)
            }
        #endif
    }
}
