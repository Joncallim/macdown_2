import Foundation

// MARK: - Increase/Decrease Indent (EPIC-22 §6.13, Slice 4c-ii)

extension EditorTextTransforms {
    /// Generalizes Tab/Shift-Tab's existing single-selection-only per-line
    /// indent engine (`MarkdownEditingAssistEngine.indentSelectedLines`/
    /// `unindentSelectedLines`, made internal for this slice — §6.13's own
    /// baseline note: this is NOT a from-scratch algorithm) to every active
    /// selection at once, as a dedicated, always-multi-selection-aware
    /// command distinct from the Tab key itself — Tab/Shift-Tab's own
    /// single-selection-only E10 assist scope (§7.2) is completely
    /// untouched by this.
    ///
    /// Line-block merging (`EditorLineTransforms.mergedLineBlockGroups`) is
    /// required for the same reason Sort/Dedupe need it: two carets on the
    /// same or adjacent lines would otherwise each independently expand to
    /// the SAME touched line(s), producing two overlapping (invalid)
    /// replacements. A DISCLOSED simplification for the resulting rare
    /// multi-caret-same-block case: every member of a merged group
    /// converges on that group's own single resulting position, rather than
    /// each preserving its own original column — the overwhelmingly common
    /// one-caret-or-selection-per-group case (this method's exact
    /// column-preserving behavior matches Tab/Shift-Tab's own single-
    /// selection result precisely) is unaffected.
    static func indentTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        width: Int,
        decrease: Bool
    ) -> EditorEditTransaction? {
        let groups = EditorLineTransforms.mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let groupStart = lineIndex.lineStartOffsets[group.startLine - 1]
            let endContentRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
            let representative = NSRange(
                location: groupStart,
                length: endContentRange.location + endContentRange.length - groupStart
            )

            let outcome = decrease
                ? MarkdownEditingAssistEngine.unindentSelectedLines(text: text, selection: representative, width: width)
                : MarkdownEditingAssistEngine.indentSelectedLines(text: text, selection: representative, width: width)
            guard case let .edit(edit) = outcome,
                  edit.replacementString != text.substring(with: edit.replacementRange)
            else {
                // A genuine no-op for this group (e.g. Decrease Indent on
                // already-flush lines) -- every member keeps its own
                // original position, shifted only by earlier groups' deltas,
                // rather than registering a wasted "replace X with X" edit.
                for index in group.memberIndices {
                    let original = selection.ranges[index]
                    resultsByOriginalIndex[index] = NSRange(
                        location: original.location + delta,
                        length: original.length
                    )
                }
                continue
            }

            replacements.append(TextReplacement(range: edit.replacementRange, replacementText: edit.replacementString))
            let resultLocation = edit.resultingSelection.location + delta
            for index in group.memberIndices {
                resultsByOriginalIndex[index] = NSRange(
                    location: resultLocation,
                    length: edit.resultingSelection.length
                )
            }

            delta += (edit.replacementString as NSString).length - edit.replacementRange.length
        }

        guard !replacements.isEmpty else { return nil }
        return EditorLineTransforms.makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: decrease ? "Decrease Indent" : "Increase Indent"
        )
    }
}
