import AppKit
import EditorCore
import FileCore

// MARK: - Convert Line Endings (EPIC-22 §6.17, Slice 8c)

extension WindowCoordinator {
    /// `true` when the key window has an active editor. Unlike the other text
    /// transforms this does not require the text view to be first responder.
    /// The status-bar item converts its own pane's text system directly; this
    /// serves the menu bar, which always targets the key window.
    var canConvertLineEndings: Bool {
        _ = commandStateRevision
        return keyLineEndingTextSystem != nil
    }

    /// Rewrites every line terminator in the key document as one undoable edit.
    @discardableResult
    func convertKeyDocumentLineEndings(to target: LineEnding) -> Bool {
        guard let system = keyLineEndingTextSystem, system.convertLineEndings(to: target) else { return false }
        system.textView.window?.makeFirstResponder(system.textView)
        return true
    }

    private var keyLineEndingTextSystem: EditorTextSystem? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let activeTab = controller.model.tabStore.activeTab
        else { return nil }
        return controller.editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
