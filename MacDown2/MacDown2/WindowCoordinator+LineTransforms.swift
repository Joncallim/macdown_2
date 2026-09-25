import AppKit
import EditorCore

// MARK: - Line-reordering transform command bridge (EPIC-22 §6.13, Slice 4c-i)

/// Mirrors `WindowCoordinator+MultiCursor.swift`'s command-bridge pattern —
/// resolve the key window's active editor, verify it is first responder,
/// then call the `EditorCore` method — and is likewise not format-restricted:
/// these are general editing commands, not Markdown-specific ones.
extension WindowCoordinator {
    /// `true` when the key window has an active editor and its text view is
    /// the first responder — i.e. these commands would apply to the active
    /// editor rather than a stale selection while focus is in the sidebar,
    /// Find UI, or another native tab.
    var canPerformLineTransform: Bool {
        // Establish an Observation dependency on AppKit focus changes,
        // exactly like `canPerformCursorCommand`. The value itself is
        // intentionally not used for the responder decision.
        _ = commandStateRevision
        guard let controller = keyLineTransformController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    @discardableResult
    func duplicateLines() -> Bool {
        performLineTransform { $0.duplicateLines() }
    }

    @discardableResult
    func deleteLines() -> Bool {
        performLineTransform { $0.deleteLines() }
    }

    @discardableResult
    func moveLinesUp() -> Bool {
        performLineTransform { $0.moveLinesUp() }
    }

    @discardableResult
    func moveLinesDown() -> Bool {
        performLineTransform { $0.moveLinesDown() }
    }

    @discardableResult
    func joinLines() -> Bool {
        performLineTransform { $0.joinLines() }
    }

    private func performLineTransform(_ perform: (EditorTextSystem) -> Bool) -> Bool {
        guard let controller = keyLineTransformController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }
        return perform(textSystem)
    }

    /// The key window's controller whose editor text system exists, for ANY
    /// document format — matching `WindowCoordinator+MultiCursor.swift`'s
    /// identical `keyEditingController`, duplicated rather than shared per
    /// this codebase's established per-file command-bridge convention.
    private var keyLineTransformController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    /// The editor text system of the active tab, if one exists yet. Mirrors
    /// `WindowCoordinator+MultiCursor.swift`'s identical private accessor —
    /// duplicated rather than shared, matching this codebase's existing
    /// per-file command-bridge pattern.
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
