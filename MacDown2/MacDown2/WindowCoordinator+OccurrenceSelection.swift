import AppKit
import EditorCore

// MARK: - Select Next/All Occurrence command bridge (EPIC-22 §6.9, Slice 3c)

/// Mirrors `WindowCoordinator+MultiCursor.swift`'s command-bridge pattern —
/// resolve the key window's active editor, verify it is first responder,
/// then call the `EditorCore` method — and is likewise not format-restricted.
///
/// `canPerformOccurrenceSelection` is also read, inverted, by
/// `WindowCoordinator+FileTree.swift`'s `keyFolderSelection` to resolve the
/// live Cmd-D conflict with Folder "Duplicate" (§6.9): both commands stay
/// declared on the same shortcut, and AppKit/SwiftUI resolves whichever one
/// is enabled by the responder chain at the moment of the keystroke.
extension WindowCoordinator {
    /// `true` when the key window has an active editor and its text view is
    /// the first responder — i.e. Select Next/All Occurrence would apply to
    /// the active editor rather than a stale selection while focus is in
    /// the sidebar, Find UI, or another native tab.
    var canPerformOccurrenceSelection: Bool {
        // Establish an Observation dependency on AppKit focus changes,
        // exactly like `canPerformCursorCommand`. The value itself is
        // intentionally not used for the responder decision.
        _ = commandStateRevision
        guard let controller = keyOccurrenceSelectionController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    /// Cmd-D. Returns `false` when any guard fails, including the text
    /// system's own decline (a bare caret touching no word, once no
    /// selection is already active).
    @discardableResult
    func selectNextOccurrence() -> Bool {
        guard let controller = keyOccurrenceSelectionController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return textSystem.selectNextOccurrence()
    }

    /// Cmd-Shift-L.
    @discardableResult
    func selectAllOccurrences() -> Bool {
        guard let controller = keyOccurrenceSelectionController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return textSystem.selectAllOccurrences()
    }

    /// The key window's controller whose editor text system exists, for ANY
    /// document format — matching `WindowCoordinator+MultiCursor.swift`'s
    /// identical `keyEditingController`, duplicated rather than shared per
    /// this codebase's established per-file command-bridge convention.
    private var keyOccurrenceSelectionController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    /// The editor text system of the active tab, if one exists yet. Mirrors
    /// `WindowCoordinator+Editing.swift`/`WindowCoordinator+MultiCursor.swift`'s
    /// identical private accessor — duplicated rather than shared, matching
    /// this codebase's existing per-file command-bridge pattern.
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
