import AppKit

// MARK: - Line-reordering transform commands (EPIC-22 §6.13, Slice 4c-i)

/// Thin adapters wiring `EditorLineTransforms`' pure logic to the live text
/// system: fetch the live text/line-index/selection, delegate, apply. Not
/// format-restricted (mirrors Add/Remove Cursor Above/Below and Select
/// Next/All Occurrence, §6.9/§6.10) — these are general editing commands,
/// not Markdown-specific ones.
public extension EditorTextSystem {
    /// Returns `false` (does nothing) when `assistTextSource` is
    /// unavailable or the transform itself reports a no-op (a boundary
    /// case, e.g. Move Up already at document start) — matching every other
    /// command-bridge method's established `@discardableResult` contract in
    /// this codebase.
    @discardableResult
    func duplicateLines() -> Bool {
        performLineTransform(EditorLineTransforms.duplicateLinesTransaction)
    }

    @discardableResult
    func deleteLines() -> Bool {
        performLineTransform(EditorLineTransforms.deleteLinesTransaction)
    }

    @discardableResult
    func moveLinesUp() -> Bool {
        performLineTransform(EditorLineTransforms.moveLinesUpTransaction)
    }

    @discardableResult
    func moveLinesDown() -> Bool {
        performLineTransform(EditorLineTransforms.moveLinesDownTransaction)
    }

    @discardableResult
    func joinLines() -> Bool {
        performLineTransform(EditorLineTransforms.joinLinesTransaction)
    }

    private func performLineTransform(
        _ transform: (NSString, EditorLineIndex, EditorSelectionSet) -> EditorEditTransaction?
    ) -> Bool {
        guard let text = assistTextSource else { return false }
        guard let transaction = transform(text, lineIndex, selectionSet) else { return false }
        apply(transaction)
        return true
    }
}
