import AppKit
import EditorCore

// MARK: - Toggle Comment command bridge (EPIC-22 §6.13, Slice 4c-iii)

/// Mirrors `WindowCoordinator+LineTransforms.swift`'s/`WindowCoordinator+TextTransforms.swift`'s
/// (Slices 4c-i/4c-ii) command-bridge pattern exactly — duplicated rather
/// than shared per this codebase's established per-file command-bridge
/// convention.
extension WindowCoordinator {
    var canToggleComment: Bool {
        _ = commandStateRevision
        guard let controller = keyCommentToggleController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    @discardableResult
    func toggleComment() -> Bool {
        guard let controller = keyCommentToggleController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return textSystem.toggleComment()
    }

    private var keyCommentToggleController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
