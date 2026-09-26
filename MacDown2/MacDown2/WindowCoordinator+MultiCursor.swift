import AppKit
import EditorCore

// MARK: - Add Cursor Above/Below command bridge (EPIC-22 §6.10, Slice 3b-ii-b)

/// Mirrors `WindowCoordinator+Editing.swift`'s Markdown/JSON command-bridge
/// pattern (resolve the key window's active editor, verify it is first
/// responder, then call the `EditorCore` method) but is deliberately NOT
/// format-restricted: multi-cursor editing applies to any document format,
/// unlike the Markdown- and JSON-specific bridges in that file.
extension WindowCoordinator {
    /// `true` when the key window has an active editor and its text view is
    /// the first responder — i.e. Add Cursor Above/Below would apply to the
    /// active editor rather than a stale selection while focus is in the
    /// sidebar, Find UI, or another native tab.
    var canPerformCursorCommand: Bool {
        // Establish an Observation dependency on AppKit focus changes,
        // exactly like `canPerformMarkdownEditingCommand`. The value itself
        // is intentionally not used for the responder decision.
        _ = commandStateRevision
        guard let controller = keyEditingController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    /// Adds a caret above the top-most existing caret in the key window's
    /// active editor. Returns `false` when any guard fails, including the
    /// top-most caret already being on the first line.
    @discardableResult
    func addCursorAbove() -> Bool {
        guard let controller = keyEditingController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return textSystem.addCursorAbove()
    }

    /// The downward counterpart of `addCursorAbove()`.
    @discardableResult
    func addCursorBelow() -> Bool {
        guard let controller = keyEditingController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return textSystem.addCursorBelow()
    }

    /// The key window's controller whose editor text system exists, for ANY
    /// document format — unlike `keyMarkdownEditingController`/
    /// `keyJSONController` in `WindowCoordinator+Editing.swift`,
    /// multi-cursor editing is not format-restricted.
    private var keyEditingController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    /// The editor text system of the active tab, if one exists yet. Mirrors
    /// `WindowCoordinator+Editing.swift`'s identical private accessor —
    /// duplicated rather than shared, matching this codebase's existing
    /// per-file command-bridge pattern (each bridge resolves its own
    /// controller/system privately; there is no shared public accessor).
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
