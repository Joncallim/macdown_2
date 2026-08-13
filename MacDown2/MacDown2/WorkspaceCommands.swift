import AppKit
import EditorCore
import SwiftUI
import Themes
import Workspace

struct WorkspaceCommands: Commands {
    @Environment(\.windowCoordinator) private var coordinator
    @FocusedValue(\.previewLayout) private var previewLayout
    private let themeController: ThemeController

    init(themeController: ThemeController) {
        self.themeController = themeController
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                coordinator?.createInKeyFolder(isDirectory: false)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(coordinator?.keyFolderRoot == nil)

            Button("New Folder") {
                coordinator?.createInKeyFolder(isDirectory: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(coordinator?.keyFolderRoot == nil)

            Button("New Tab") {
                coordinator?.newDocument(addAsTab: true)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Open…") {
                coordinator?.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                coordinator?.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Open Recent Folder") {
                ForEach(coordinator?.recentFolderRoots.roots ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { coordinator?.openRecentFolder(url) }
                }
                Divider()
                Button("Clear Menu") { coordinator?.recentFolderRoots.clear() }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                coordinator?.saveKeyDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(coordinator?.keyModel?.canSave != true)

            Button("Save As…") {
                coordinator?.saveKeyDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            Button("Close Tab") {
                coordinator?.closeKeyWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(coordinator?.keyModel?.canClose != true)
        }

        CommandMenu("Folder") {
            Button("Rename") {
                coordinator?.renameKeyFolderSelection()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(coordinator?.keyFolderSelection == nil)

            Button("Duplicate") {
                coordinator?.duplicateKeyFolderSelection()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(coordinator?.keyFolderSelection == nil)

            Button("Move to Trash", role: .destructive) {
                coordinator?.trashKeyFolderSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(coordinator?.keyFolderSelection == nil)
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
            Menu("Layout") {
                let layout = previewLayout ?? .defaultMode

                Button(
                    action: { setPreviewLayout(.editorOnly) },
                    label: {
                        Text((layout == .editorOnly ? "✓ " : "    ") + "Editor Only")
                    }
                )
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(
                    action: { setPreviewLayout(.split(fraction: 0.5)) },
                    label: {
                        if case .split = layout {
                            Text("✓ Split Editor & Preview")
                        } else {
                            Text("    Split Editor & Preview")
                        }
                    }
                )
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button(
                    action: { setPreviewLayout(.previewOnly) },
                    label: {
                        Text((layout == .previewOnly ? "✓ " : "    ") + "Preview Only")
                    }
                )
                .keyboardShortcut("3", modifiers: [.command, .option])
            }

            Menu("Theme") {
                let active = themeController.current
                let lightThemes = themeController.available.filter { $0.appearance == .light }
                let darkThemes = themeController.available.filter { $0.appearance == .dark }

                Section("Light") {
                    ForEach(lightThemes) { theme in
                        Button(
                            action: { themeController.select(theme) },
                            label: {
                                Text((active.id == theme.id ? "✓ " : "    ") + theme.name)
                            }
                        )
                    }
                }

                Section("Dark") {
                    ForEach(darkThemes) { theme in
                        Button(
                            action: { themeController.select(theme) },
                            label: {
                                Text((active.id == theme.id ? "✓ " : "    ") + theme.name)
                            }
                        )
                    }
                }
            }

            Button("Toggle Sidebar") {
                coordinator?.keyModel?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            Button("Focus Outline") {
                coordinator?.focusOutline()
            }
            .keyboardShortcut("o", modifiers: [.control, .command])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            Button("Reveal Active File") {
                coordinator?.revealActiveFile()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .disabled(coordinator?.keyModel?.activeDocument?.fileURL == nil)
        }

        // E10: the editor is plain text (`isRichText = false`), so the rich
        // text Format menu is replaced with Markdown formatting commands.
        // `.textEditing` (Find, spelling, substitutions) is intentionally
        // left untouched — in particular ⌘E keeps AppKit's "Use Selection
        // for Find" behavior, and Inline Code is ⌃⌘E.
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") {
                coordinator?.performMarkdownEditingCommand(.bold)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(coordinator?.canPerformMarkdownEditingCommand != true)

            Button("Italic") {
                coordinator?.performMarkdownEditingCommand(.italic)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(coordinator?.canPerformMarkdownEditingCommand != true)

            Button("Inline Code") {
                coordinator?.performMarkdownEditingCommand(.inlineCode)
            }
            .keyboardShortcut("e", modifiers: [.control, .command])
            .disabled(coordinator?.canPerformMarkdownEditingCommand != true)

            Divider()

            Menu("Heading") {
                ForEach(1 ... 6, id: \.self) { level in
                    Button("Heading \(level)") {
                        coordinator?.performMarkdownEditingCommand(.heading(level: level))
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.control, .command])
                    .disabled(coordinator?.canPerformMarkdownEditingCommand != true)
                }

                Divider()

                Button("Paragraph") {
                    coordinator?.performMarkdownEditingCommand(.paragraph)
                }
                .keyboardShortcut("0", modifiers: [.control, .command])
                .disabled(coordinator?.canPerformMarkdownEditingCommand != true)
            }
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

    private func setPreviewLayout(_ layout: PreviewLayoutMode) {
        coordinator?.setPreviewLayout(layout)
    }
}

// MARK: - Focused layout state

/// Key for the active tab's preview layout so `Commands` can reactively update
/// the Layout menu checkmark. The value is published from the key window's
/// shell view via `.focusedSceneValue`.
private struct PreviewLayoutFocusedValueKey: FocusedValueKey {
    typealias Value = PreviewLayoutMode
}

extension FocusedValues {
    var previewLayout: PreviewLayoutMode? {
        get { self[PreviewLayoutFocusedValueKey.self] }
        set { self[PreviewLayoutFocusedValueKey.self] = newValue }
    }
}
