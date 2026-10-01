import AppKit

extension EditorView.Coordinator {
    /// Return where no assist applies would let AppKit insert a bare `\n`,
    /// adding a second line-ending convention to a CRLF (or bare-CR) document
    /// — invariant #5. When the engine would pass the key through and the
    /// document's own separator is not `\n`, insert that separator instead.
    /// Fails open (returns `false`) for IME composition, read-only editors,
    /// multiple selections and the programmatic-update guards.
    @MainActor func handleLineEndingAwareNewline(_ textView: NSTextView, system: EditorTextSystem) -> Bool {
        guard !isApplyingModelText,
              !system.isPerformingProgrammaticTextUpdate,
              !system.isPerformingEditingAssist,
              !textView.hasMarkedText(),
              textView.isEditable,
              textView.selectedRanges.count == 1,
              let source = system.assistTextSource
        else { return false }
        let selection = system.selectedRange
        if system.editingAssistConfiguration.isEnabled {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .insertNewline,
                text: source,
                selection: selection,
                configuration: system.editingAssistConfiguration,
                profile: system.languageEditingProfile
            )
            guard outcome == .passthrough else { return false }
        }
        let separator = MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: selection.location, in: source)
        guard separator != "\n" else { return false }
        return system.applyAssistOutcome(.edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: separator,
            resultingSelection: NSRange(location: selection.location + separator.utf16.count, length: 0),
            undoActionName: "Typing"
        )))
    }
}
