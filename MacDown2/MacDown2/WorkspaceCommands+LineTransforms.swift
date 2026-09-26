import EditorCore
import SwiftUI

// MARK: - Line transform commands (EPIC-22 §6.13, Slices 4c-i/4c-ii)

/// Extracted from `WorkspaceCommands.swift` to keep that type's own body
/// under its line-count limit, mirroring `WorkspaceCommands+TextFormatting.swift`'s
/// established per-feature-file split precedent. A dedicated `CommandMenu`
/// (not folded into `.textFormatting`, whose own commands are all either
/// Markdown-specific or multi-cursor-focused) since these are general
/// whole-line editing commands, matching how BBEdit/Sublime give this exact
/// command family its own "Text"/"Edit ▸ Lines" menu location.
///
/// Slice 4c-ii's own Sort/Dedupe/Trim/Convert Case/Indent commands
/// (`WindowCoordinator+TextTransforms.swift`) are added directly into this
/// SAME `CommandMenu` below, rather than each sub-slice getting its own
/// `CommandMenu("Lines")` in a separate file — declaring two identically-
/// named `CommandMenu`s produces two SEPARATE sibling menus in the actual
/// menu bar (a real SwiftUI `Commands` behavior, not a cosmetic choice), so
/// this file is the one deliberate exception to this epic's usual "each
/// sub-slice gets its own app-target file" convention.
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

            Divider()

            Button("Sort Lines") {
                coordinator?.sortLines()
            }
            .disabled(coordinator?.canPerformTextTransform != true)

            Button("Remove Duplicate Lines") {
                coordinator?.dedupeLines()
            }
            .disabled(coordinator?.canPerformTextTransform != true)

            Button("Trim Trailing Whitespace") {
                coordinator?.trimTrailingWhitespace()
            }
            .disabled(coordinator?.canPerformTextTransform != true)

            Divider()

            Menu("Convert Case") {
                Button("Uppercase") {
                    coordinator?.convertCase(.uppercase)
                }
                .disabled(coordinator?.canPerformTextTransform != true)

                Button("Lowercase") {
                    coordinator?.convertCase(.lowercase)
                }
                .disabled(coordinator?.canPerformTextTransform != true)

                Button("Capitalize") {
                    coordinator?.convertCase(.capitalized)
                }
                .disabled(coordinator?.canPerformTextTransform != true)
            }

            Divider()

            Button("Increase Indent") {
                coordinator?.increaseIndent()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(coordinator?.canPerformTextTransform != true)

            Button("Decrease Indent") {
                coordinator?.decreaseIndent()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(coordinator?.canPerformTextTransform != true)

            Divider()

            // EPIC-22 §6.13, Slice 4c-iii: not gated on `canPerformTextTransform`
            // (which only checks first-responder) -- the pure engine itself
            // declines when the effective profile has no comment syntax at
            // all (e.g. JSON), so the menu item's own enabled state is
            // deliberately not format-restricted here either, matching
            // every other command in this menu.
            Button("Toggle Comment") {
                coordinator?.toggleComment()
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(coordinator?.canToggleComment != true)
        }
    }
}
