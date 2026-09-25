import AppKit

// MARK: - Select Next/All Occurrence (EPIC-22 §6.9, Slice 3c)

public extension EditorTextSystem {
    /// Cmd-D. From a bare caret, selects the word at/touching the caret and
    /// stops there — matching Sublime Text/VS Code's own Cmd-D convention,
    /// this first press does NOT also jump to a second occurrence. From an
    /// existing (non-empty) selection, finds the next occurrence of that
    /// selection's own literal text (case-sensitive substring match, not
    /// restricted to whole-word boundaries — a word selected by the first
    /// press can still match inside a longer identifier later) starting
    /// just after the current primary's own end, wraps to the document
    /// start if not found before the end, and adds it to the selection set
    /// as the new primary. Skips any occurrence already present in the
    /// selection set, so a further press once every occurrence in the
    /// document is already selected is a correct no-op, not a re-add.
    ///
    /// `false` when there is no active editor state to act on: a bare
    /// caret touching no word, an IME composition in progress, or a
    /// currently-in-progress editing assist/programmatic text update.
    @discardableResult
    func selectNextOccurrence() -> Bool {
        guard !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let text = textView.string as NSString
        var selection = selectionSet

        guard selection.primaryRange.length > 0 else {
            guard let word = Self.wordRange(at: selection.primaryRange.location, in: text) else { return false }
            selectionSet = EditorSelectionSet(single: word)
            return true
        }

        let searchText = text.substring(with: selection.primaryRange)
        let occurrences = Self.allOccurrenceRanges(of: searchText, in: text)
        guard !occurrences.isEmpty else { return false }

        let primaryEnd = selection.primaryRange.location + selection.primaryRange.length
        let ordered = occurrences.filter { $0.location >= primaryEnd } + occurrences.filter { $0.location < primaryEnd }
        guard let next = ordered.first(where: { !selection.ranges.contains($0) }) else { return false }

        selection.addRange(next, makePrimary: true)
        selectionSet = selection
        return true
    }

    /// Cmd-Shift-L. Same text-to-match derivation as `selectNextOccurrence()`
    /// (the primary selection's own text, or the word at the caret if there
    /// is none) but replaces `selectionSet` wholesale with every occurrence
    /// in the document in one call — usable standalone from a bare caret,
    /// not only as a continuation of repeated `selectNextOccurrence()`
    /// presses.
    @discardableResult
    func selectAllOccurrences() -> Bool {
        guard !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let text = textView.string as NSString
        let selection = selectionSet

        let searchText: String
        if selection.primaryRange.length > 0 {
            searchText = text.substring(with: selection.primaryRange)
        } else {
            guard let word = Self.wordRange(at: selection.primaryRange.location, in: text) else { return false }
            searchText = text.substring(with: word)
        }

        let occurrences = Self.allOccurrenceRanges(of: searchText, in: text)
        guard !occurrences.isEmpty else { return false }

        let primaryLocation = selection.primaryRange.location
        let primaryIndex = occurrences
            .firstIndex { $0.location <= primaryLocation && primaryLocation <= $0.location + $0.length } ?? 0
        selectionSet = EditorSelectionSet(ranges: occurrences, primaryIndex: primaryIndex)
        return true
    }

    /// Matches `TextSearchEngine`'s own `wordCharacters` definition
    /// (`CharacterSet.alphanumerics` + `_`) — duplicated rather than
    /// imported, since `EditorCore` and `TextSearch` are sibling package
    /// targets with no dependency between them (mirroring `TextSearchEngine`'s
    /// own documented reason for duplicating its scalar-boundary helpers
    /// rather than depending on `EditorCore`, the identical constraint in
    /// the opposite direction).
    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        wordCharacters.contains(scalar)
    }

    /// The maximal run of word characters at or touching `offset`, or `nil`
    /// if `offset` touches no word on either side. Reuses
    /// `MarkdownEditingAssistEngine`'s existing scalar-boundary helpers
    /// (same module, already surrogate-pair-safe) rather than testing raw
    /// UTF-16 units directly.
    private static func wordRange(at offset: Int, in text: NSString) -> NSRange? {
        if let scalar = MarkdownEditingAssistEngine.scalar(at: offset, in: text), isWordScalar(scalar) {
            return expandedWordRange(fromStart: offset, in: text)
        }
        if let scalar = MarkdownEditingAssistEngine.scalar(before: offset, in: text), isWordScalar(scalar) {
            return expandedWordRange(fromStart: offset - MarkdownEditingAssistEngine.utf16Length(of: scalar), in: text)
        }
        return nil
    }

    /// Expands outward from a UTF-16 index already confirmed to be the
    /// start of a word scalar, in both directions, to the word's full
    /// extent.
    private static func expandedWordRange(fromStart anchor: Int, in text: NSString) -> NSRange {
        var start = anchor
        while let scalar = MarkdownEditingAssistEngine.scalar(before: start, in: text), isWordScalar(scalar) {
            start -= MarkdownEditingAssistEngine.utf16Length(of: scalar)
        }
        var end = anchor
        while let scalar = MarkdownEditingAssistEngine.scalar(at: end, in: text), isWordScalar(scalar) {
            end += MarkdownEditingAssistEngine.utf16Length(of: scalar)
        }
        return NSRange(location: start, length: end - start)
    }

    /// Every non-overlapping literal (case-sensitive) occurrence of
    /// `searchText` in `text`, in ascending document order. `searchText` is
    /// never empty at any call site above, so each match advances the scan
    /// past its own end — this cannot loop forever.
    private static func allOccurrenceRanges(of searchText: String, in text: NSString) -> [NSRange] {
        guard !searchText.isEmpty else { return [] }
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart <= text.length {
            let found = text.range(
                of: searchText,
                options: [.literal],
                range: NSRange(location: searchStart, length: text.length - searchStart)
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            searchStart = found.location + found.length
        }
        return ranges
    }
}
