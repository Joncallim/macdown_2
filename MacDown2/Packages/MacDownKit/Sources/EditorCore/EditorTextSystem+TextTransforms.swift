import AppKit

// MARK: - Sort/Dedupe/Trim/Case/Indent transform commands (EPIC-22 §6.13, Slice 4c-ii)

/// Thin adapters wiring `EditorTextTransforms`' pure logic to the live text
/// system, mirroring `EditorTextSystem+LineTransforms.swift`'s (Slice 4c-i)
/// established shape. Not format-restricted.
public extension EditorTextSystem {
    @discardableResult
    func sortLines() -> Bool {
        performTextTransform { text, lineIndex, selection in
            EditorTextTransforms.sortLinesTransaction(text: text, lineIndex: lineIndex, selection: selection)
        }
    }

    @discardableResult
    func dedupeLines() -> Bool {
        performTextTransform { text, lineIndex, selection in
            EditorTextTransforms.dedupeLinesTransaction(text: text, lineIndex: lineIndex, selection: selection)
        }
    }

    @discardableResult
    func trimTrailingWhitespace() -> Bool {
        performTextTransform { text, lineIndex, selection in
            EditorTextTransforms.trimTrailingWhitespaceTransaction(
                text: text,
                lineIndex: lineIndex,
                selection: selection
            )
        }
    }

    @discardableResult
    func convertCase(_ conversion: TextCaseConversion) -> Bool {
        performTextTransform { text, _, selection in
            EditorTextTransforms.convertCaseTransaction(text: text, selection: selection, conversion: conversion)
        }
    }

    /// `width` resolves the same way `MarkdownEditingAssistEngine.tabOutcome`
    /// already resolves Tab/Shift-Tab's own effective width: a format's own
    /// profile overrides the global indentation-width preference.
    @discardableResult
    func increaseIndent() -> Bool {
        performIndentTransform(decrease: false)
    }

    @discardableResult
    func decreaseIndent() -> Bool {
        performIndentTransform(decrease: true)
    }

    private func performIndentTransform(decrease: Bool) -> Bool {
        let width = languageEditingProfile.defaultIndentWidth ?? editingAssistConfiguration.indentationWidth
        return performTextTransform { text, lineIndex, selection in
            EditorTextTransforms.indentTransaction(
                text: text,
                lineIndex: lineIndex,
                selection: selection,
                width: width,
                decrease: decrease
            )
        }
    }

    private func performTextTransform(
        _ transform: (NSString, EditorLineIndex, EditorSelectionSet) -> EditorEditTransaction?
    ) -> Bool {
        guard let text = assistTextSource else { return false }
        guard let transaction = transform(text, lineIndex, selectionSet) else { return false }
        apply(transaction)
        return true
    }
}
