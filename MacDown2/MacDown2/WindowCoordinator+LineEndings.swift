import AppKit
import EditorCore
import FileCore

// MARK: - Convert Line Endings (EPIC-22 §6.17, Slice 8c)

extension WindowCoordinator {
    /// `true` when the key window has an active editor. Unlike the other text
    /// transforms this does not require the text view to be first responder:
    /// the status-bar item is a menu, and clicking it need not move focus.
    var canConvertLineEndings: Bool {
        _ = commandStateRevision
        return keyLineEndingTextSystem != nil
    }

    /// The key document's terminators as they are right now, or `nil` when
    /// there is no key editor.
    var keyDocumentLineEndingProfile: LineEndingProfile? {
        keyLineEndingTextSystem.map { LineEndingProfile(detecting: $0.text) }
    }

    /// Rewrites every line terminator in the key document as one undoable edit.
    @discardableResult
    func convertKeyDocumentLineEndings(to target: LineEnding) -> Bool {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let system = keyLineEndingTextSystem
        else { return false }
        controller.window?.makeFirstResponder(system.textView)
        return system.convertLineEndings(to: target)
    }

    private var keyLineEndingTextSystem: EditorTextSystem? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let activeTab = controller.model.tabStore.activeTab
        else { return nil }
        return controller.editorStore.existingSystem(for: activeTab.id.uuidString)
    }
}
