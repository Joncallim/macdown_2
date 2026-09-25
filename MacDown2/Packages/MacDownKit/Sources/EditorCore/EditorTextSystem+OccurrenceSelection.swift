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
    /// as the new primary. Skips any occurrence that OVERLAPS an existing
    /// selection (not just an exact duplicate — see
    /// `firstOccurrence(of:in:searchingFrom:notOverlapping:)`'s own doc
    /// comment for why that distinction matters for a self-overlapping
    /// search string), so a further press once every occurrence in the
    /// document is already selected, or every remaining candidate would
    /// overlap what is already selected, is a correct no-op rather than a
    /// re-add or a silent, corrupting merge.
    ///
    /// `false` when there is no active editor state to act on: a bare
    /// caret touching no word, an IME composition in progress, a
    /// currently-in-progress editing assist/programmatic text update, or no
    /// remaining occurrence that doesn't overlap the current selection.
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
        let primaryEnd = selection.primaryRange.location + selection.primaryRange.length
        let next = Self.firstOccurrence(
            of: searchText,
            in: text,
            searchingFrom: primaryEnd,
            notOverlapping: selection.ranges
        )
            ?? Self.firstOccurrence(of: searchText, in: text, searchingFrom: 0, notOverlapping: selection.ranges)
        guard let next else { return false }

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
    ///
    /// Disclosed, accepted edge case (found by an independent hostile
    /// review, not fixed — a genuinely ambiguous UX question, not a
    /// corruption bug the way `selectNextOccurrence()`'s own self-overlap
    /// case was): if the current primary is a MANUALLY selected
    /// self-overlapping range (e.g. the middle `"aa"` at offset 1 of
    /// `"aaaa"` — the word-selection path can never produce this, since
    /// `"a"` alone has no self-overlap boundary to land on), the new
    /// primary after this call is whichever non-overlapping tiled
    /// occurrence CONTAINS that location, which may not be the exact range
    /// the user had selected. This never corrupts the selection the way
    /// the original `selectNextOccurrence()` bug did — `occurrences` here
    /// is always a valid, non-overlapping `EditorSelectionSet` — it can
    /// only pick a different, still-correct-for-the-search-text primary
    /// than the one the user started from.
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
    /// `searchText` in `text`, in ascending document order — the correct,
    /// only-workable semantic for `selectAllOccurrences()` specifically:
    /// `EditorSelectionSet` cannot represent overlapping ranges at all, so
    /// "select every occurrence" of a self-overlapping pattern (e.g. `"aa"`
    /// in `"aaaa"`) necessarily means the non-overlapping tiling, exactly
    /// like a real editor's own "Find All" would produce. `searchText` is
    /// never empty at any call site above, so each match advances the scan
    /// past its own end — this cannot loop forever.
    ///
    /// NOT used by `selectNextOccurrence()`'s own "find the next occurrence
    /// after the current primary" step — see `firstOccurrence(of:in:searchingFrom:notOverlapping:)`'s
    /// own doc comment for why a whole-document greedy tiling is the wrong
    /// tool there specifically.
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

    /// The first occurrence of `searchText` at or after `start` that does
    /// NOT overlap any range in `existing`, or `nil` if none exists before
    /// the end of the document.
    ///
    /// Skips on OVERLAP, not mere exact-match, and deliberately advances
    /// the scan by exactly one UTF-16 unit past a skipped candidate, not
    /// past that candidate's own end, so a self-overlapping search string
    /// (e.g. `"aa"` in `"aaaa"`) is still searched correctly. Both
    /// properties matter together: an independent hostile review of this
    /// slice found an earlier version of this method skipped only on exact
    /// `NSRange` equality, which is not enough — even a genuinely NEW,
    /// not-previously-selected candidate can still overlap an existing
    /// selection for a self-overlapping pattern (the middle `"aa"` at
    /// offset 1 of `"aaaa"`, selected manually rather than via the
    /// word-selection path, has `"aa"` at offset 0 as a distinct-but-
    /// overlapping neighbor), and adding an overlapping range would still
    /// hit `EditorSelectionSet.normalize`'s own overlap-merge rule,
    /// collapsing the result into one larger, no-longer-matching range
    /// while this method still reported success. Skipping on overlap
    /// (rather than exact match) means every candidate this method ever
    /// returns is genuinely safe to add via `EditorSelectionSet.addRange(_:makePrimary:)`
    /// without triggering that merge — and correctly declining (returning
    /// `nil` from both the forward and wraparound searches) for the
    /// `"aaaa"` case above, since literally every possible `"aa"` position
    /// there overlaps the existing selection: there is no valid "next
    /// occurrence" to add, and reporting that honestly is strictly better
    /// than corrupting the selection while claiming success.
    private static func firstOccurrence(
        of searchText: String,
        in text: NSString,
        searchingFrom start: Int,
        notOverlapping existing: [NSRange]
    ) -> NSRange? {
        var searchStart = start
        while searchStart <= text.length {
            let found = text.range(
                of: searchText,
                options: [.literal],
                range: NSRange(location: searchStart, length: text.length - searchStart)
            )
            guard found.location != NSNotFound else { return nil }
            guard existing.contains(where: { overlaps($0, found) }) else { return found }
            searchStart = found.location + 1
        }
        return nil
    }

    /// Standard half-open-interval overlap test, agreeing with
    /// `EditorSelectionSet.normalize`'s own overlap condition. `first` here
    /// is always a fresh search match, so its `length` is always the search
    /// text's own length (every call site guards that to be non-empty);
    /// `second` (an existing selection range) can legitimately be
    /// zero-length (a bare caret from another cursor in a multi-cursor
    /// session) — the formula is still correct for that case, since a
    /// zero-length range simply can never satisfy `second.location <
    /// first.location + first.length` for any `first` it doesn't already
    /// contain (this function does not need `normalize`'s own separate
    /// "duplicate caret" special case, which exists only to make two
    /// zero-length ranges AT THE SAME point merge — not a distinction that
    /// matters when only one side of the comparison can ever be
    /// zero-length).
    private static func overlaps(_ first: NSRange, _ second: NSRange) -> Bool {
        first.location < second.location + second.length && second.location < first.location + first.length
    }
}
