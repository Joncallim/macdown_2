import AppKit
import EditorCore

// MARK: - Sort/Dedupe/Trim/Case/Indent transform command bridge (EPIC-22 §6.13, Slice 4c-ii)

/// Mirrors `WindowCoordinator+LineTransforms.swift`'s (Slice 4c-i) command-
/// bridge pattern exactly — resolve the key window's active editor, verify
/// it is first responder, then call the `EditorCore` method — duplicated
/// rather than shared per this codebase's established per-file command-
/// bridge convention.
extension WindowCoordinator {
    /// `true` when the key window has an active editor and its text view is
    /// the first responder.
    var canPerformTextTransform: Bool {
        _ = commandStateRevision
        guard let controller = keyTextTransformController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    @discardableResult
    func sortLines() -> Bool {
        performTextTransform { $0.sortLines() }
    }

    @discardableResult
    func dedupeLines() -> Bool {
        performTextTransform { $0.dedupeLines() }
    }

    @discardableResult
    func trimTrailingWhitespace() -> Bool {
        performTextTransform { $0.trimTrailingWhitespace() }
    }

    @discardableResult
    func convertCase(_ conversion: TextCaseConversion) -> Bool {
        performTextTransform { $0.convertCase(conversion) }
    }

    @discardableResult
    func increaseIndent() -> Bool {
        performTextTransform { $0.increaseIndent() }
    }

    @discardableResult
    func decreaseIndent() -> Bool {
        performTextTransform { $0.decreaseIndent() }
    }

    private func performTextTransform(_ perform: (EditorTextSystem) -> Bool) -> Bool {
        guard let controller = keyTextTransformController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return perform(textSystem)
    }

    private var keyTextTransformController: WindowController? {
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
