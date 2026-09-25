import EditorCore
import SwiftUI

// MARK: - Line-reordering transform commands (EPIC-22 §6.13, Slice 4c-i)

/// Extracted from `WorkspaceCommands.swift` to keep that type's own body
/// under its line-count limit, mirroring `WorkspaceCommands+TextFormatting.swift`'s
/// established per-feature-file split precedent. A dedicated `CommandMenu`
/// (not folded into `.textFormatting`, whose own commands are all either
/// Markdown-specific or multi-cursor-focused) since these are general
/// whole-line editing commands, matching how BBEdit/Sublime give this exact
/// command family its own "Text"/"Edit ▸ Lines" menu location.
extension WorkspaceCommands {
    var lineTransformCommands: some Commands {
        CommandMenu("Lines") {
            Button("Duplicate Line") {
                coordinator?.duplicateLines()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(coordinator?.canPerformLineTransform != true)

            Button("Delete Line") {
                coordinator?.deleteLines()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(coordinator?.canPerformLineTransform != true)

            Divider()

            Button("Move Line Up") {
                coordinator?.moveLinesUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(coordinator?.canPerformLineTransform != true)

            Button("Move Line Down") {
                coordinator?.moveLinesDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(coordinator?.canPerformLineTransform != true)

            Divider()

            Button("Join Lines") {
                coordinator?.joinLines()
            }
            .keyboardShortcut("j", modifiers: [.control])
            .disabled(coordinator?.canPerformLineTransform != true)
        }
    }
}
