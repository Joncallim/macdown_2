import EditorCore
import SwiftUI

// MARK: - Text formatting / multi-cursor / occurrence-selection commands

/// Extracted from `WorkspaceCommands.swift` to keep that type's own body
/// under its line-count limit, mirroring the established per-feature-file
/// split precedent (`EditorView+Coordinator+Movement.swift`, etc.).
extension WorkspaceCommands {
    /// E10: the editor is plain text (`isRichText = false`), so the rich
    /// text Format menu is replaced with Markdown formatting commands.
    /// `.textEditing` (Find, spelling, substitutions) is intentionally left
    /// untouched — in particular ⌘E keeps AppKit's "Use Selection for Find"
    /// behavior, and Inline Code is ⌃⌘E.
    var textFormattingCommands: some Commands {
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

            Divider()

            // E11 Gate 2: deterministic JSON formatting. Disabled for
            // non-JSON documents and for invalid JSON (the analysis session
            // must verify the current text is a valid document first).
            Button("Format JSON") {
                Task { await coordinator?.performJSONFormatting(sortKeys: false) }
            }
            .keyboardShortcut("f", modifiers: [.option, .command])
            .disabled(coordinator?.canPerformJSONFormatting != true)

            Button("Format JSON with Sorted Keys") {
                Task { await coordinator?.performJSONFormatting(sortKeys: true) }
            }
            .keyboardShortcut("f", modifiers: [.option, .shift, .command])
            .disabled(coordinator?.canPerformJSONFormatting != true)

            Divider()

            // EPIC-22 §6.10, Slice 3b-ii-b: not format-restricted, unlike
            // the Markdown/JSON commands above — ⌃⌘↑/⌃⌘↓ matches Xcode's
            // own established convention for the same feature.
            Button("Add Cursor Above") {
                coordinator?.addCursorAbove()
            }
            .keyboardShortcut(.upArrow, modifiers: [.control, .command])
            .disabled(coordinator?.canPerformCursorCommand != true)

            Button("Add Cursor Below") {
                coordinator?.addCursorBelow()
            }
            .keyboardShortcut(.downArrow, modifiers: [.control, .command])
            .disabled(coordinator?.canPerformCursorCommand != true)

            Divider()

            // EPIC-22 §6.9, Slice 3c: also not format-restricted. Declared
            // on the same "d" shortcut as Folder "Duplicate" — only one of
            // the two is ever enabled at a time, resolved by the responder
            // chain at the moment of the keystroke (see `keyFolderSelection`'s
            // own doc comment for the fix on the other side of this
            // conflict).
            Button("Select Next Occurrence") {
                coordinator?.selectNextOccurrence()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(coordinator?.canPerformOccurrenceSelection != true)

            Button("Select All Occurrences") {
                coordinator?.selectAllOccurrences()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(coordinator?.canPerformOccurrenceSelection != true)
        }
    }
}
