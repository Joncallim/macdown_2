import AppKit
import EditorCore

// MARK: - Markdown formatting command bridge

/// E10 command seam between the SwiftUI menu (`WorkspaceCommands`) and the
/// active editor's `EditorTextSystem`.
///
/// The bridge repeats every safety guard itself; menu enablement via
/// `canPerformMarkdownEditingCommand` is convenience, not a safety boundary.
extension WindowCoordinator {
    /// `true` when the key window's active document is Markdown, its editor
    /// text system exists with assists enabled, and the editor text view is
    /// the first responder — i.e. a formatting command would apply to the
    /// active editor rather than a stale selection.
    var canPerformMarkdownEditingCommand: Bool {
        // Establish an Observation dependency on AppKit focus changes. The
        // value itself is intentionally not used for the responder decision.
        _ = commandStateRevision
        guard let controller = keyMarkdownEditingController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    /// Applies a Markdown formatting command to the key window's active
    /// editor. Returns `false` when any guard fails (including the text
    /// system's own disabled configuration).
    @discardableResult
    func performMarkdownEditingCommand(_ command: MarkdownEditingCommand) -> Bool {
        guard let controller = keyMarkdownEditingController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }

        // Do not apply a formatting command to a stale selection when focus
        // is in the sidebar, Find UI, or another native tab.
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }

        return textSystem.performMarkdownCommand(command)
    }

    /// The key window's controller whose active document is Markdown and whose
    /// editor text system exists.
    private var keyMarkdownEditingController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.model.activeDocument?.format.id == "markdown",
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    /// The editor text system of the active tab, if one exists yet.
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
