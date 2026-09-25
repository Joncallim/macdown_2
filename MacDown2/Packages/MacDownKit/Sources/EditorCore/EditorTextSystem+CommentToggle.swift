import AppKit

// MARK: - Toggle Comment command (EPIC-22 §6.13, Slice 4c-iii)

/// Thin adapter wiring `EditorCommentToggle`'s pure logic to the live text
/// system, mirroring `EditorTextSystem+LineTransforms.swift`'s (Slice 4c-i)
/// established shape. Not format-restricted at the type-check level — the
/// pure engine itself declines when the effective profile has no comment
/// syntax at all, which is what actually disables this for e.g. JSON/plain
/// text.
public extension EditorTextSystem {
    @discardableResult
    func toggleComment() -> Bool {
        guard let text = assistTextSource else { return false }
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selectionSet,
            isMarkdownFormat: editingAssistConfiguration.isMarkdownFormat,
            profile: languageEditingProfile
        )
        guard let transaction else { return false }
        apply(transaction)
        return true
    }
}
