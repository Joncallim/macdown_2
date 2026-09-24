import AppKit

// MARK: - Multi-selection typing/delete (EPIC-22 §6.9, §7.2, Slice 3a)

extension EditorTextSystem {
    /// Called by `EditorTextView.insertText(_:replacementRange:)` — that
    /// override, not `NSTextViewDelegate`'s array-based
    /// `shouldChangeTextInRanges:replacementStrings:`, is the real
    /// interception point. That delegate method was tried first and found,
    /// empirically (`EditorMultiSelectionTests` against a real mounted
    /// `NSTextView`), to never be invoked by ordinary
    /// `insertText(_:replacementRange:)`/`deleteBackward(_:)` regardless of
    /// how many `selectedRanges` are active — AppKit acts only on the
    /// primary selection for a plain keystroke, never fanning it out on its
    /// own.
    ///
    /// `selectionSet.ranges.count > 1` implies every one of those ranges is
    /// non-empty: confirmed empirically that `NSTextView.selectedRanges`
    /// collapses to a single range the instant more than one zero-length
    /// (bare caret) range — or any mix of a zero-length range with anything
    /// else — is assigned to it, so a genuine multi-*caret* state can never
    /// reach here in the first place (§6.9's architecture-correction note).
    /// This method therefore only ever fires for real, multiple selections
    /// (exactly what Select-All-Occurrence, Slice 3c, produces): typing
    /// replaces every one of them with the same text simultaneously,
    /// analogous to typing over one ordinary selection.
    ///
    /// Returns `true` when this method has already applied the edit (the
    /// override must not also call `super`, or the edit would double-apply
    /// at the primary selection and simply not happen at the others);
    /// `false` to fall through to AppKit's normal single-range handling
    /// unchanged — fewer than two active selections (the overwhelmingly
    /// common case, left entirely to AppKit/E10's existing single-range
    /// path), an active IME composition (fails open, matching every other
    /// IME gate in this codebase), or a currently-in-progress editing
    /// assist/programmatic text update (this call is itself part of one, so
    /// re-entering would double-apply).
    func applyMultiCursorInsert(_ text: String) -> Bool {
        let ranges = selectionSet.ranges
        guard ranges.count > 1 else { return false }
        guard !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let replacements = ranges.map { TextReplacement(range: $0, replacementText: text) }
        applyMultiCursorTransaction(replacements)
        return true
    }

    /// The delete counterpart of `applyMultiCursorInsert(_:)`, called by
    /// both `EditorTextView.deleteBackward(_:)` and `deleteForward(_:)`.
    /// Per that method's doc comment, every range in a `count > 1`
    /// `selectionSet` is guaranteed non-empty, so deleting each selection's
    /// own content is direction-independent — exactly like pressing either
    /// delete key with one ordinary selection active, which is why there is
    /// no separate forward/backward variant here.
    func applyMultiCursorDeleteSelection() -> Bool {
        let ranges = selectionSet.ranges
        guard ranges.count > 1 else { return false }
        guard !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let replacements = ranges.map { TextReplacement(range: $0, replacementText: "") }
        applyMultiCursorTransaction(replacements)
        return true
    }

    /// Fails open (does nothing) on a `replacements` set
    /// `EditorEditTransaction.validate` rejects, rather than calling
    /// `apply(_:)` with input that method's own Debug-fatal validation
    /// would trap on — this call site guarantees well-formed input instead
    /// of relying on that trap, matching this codebase's established
    /// "fail closed on malformed multi-range input" discipline. In
    /// practice `selectionSet.ranges` is already normalized (sorted,
    /// non-overlapping) by `EditorSelectionSet` itself, so this should
    /// never actually reject; it is defense in depth, not a case this
    /// slice's tests need to force.
    private func applyMultiCursorTransaction(_ replacements: [TextReplacement]) {
        let documentLength = textView.textStorage?.length ?? 0
        guard EditorEditTransaction.validate(replacements, documentLength: documentLength) else { return }
        let resultingSelection = EditorSelectionSet(
            ranges: EditorEditTransaction.resultingCaretRanges(for: replacements),
            primaryIndex: 0
        )
        apply(EditorEditTransaction(replacements: replacements, resultingSelection: resultingSelection))
    }
}
