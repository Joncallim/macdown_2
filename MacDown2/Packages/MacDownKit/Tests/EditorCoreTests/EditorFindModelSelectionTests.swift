@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// EPIC-22 §6.14, Slice 5c — `EditorFindModel.selectionSetForAllMatches`
/// (Select All Matches) and `updateMatches(in:selection:)`'s
/// `options.searchesSelectionOnly` support, entirely independent of
/// `NSTextView`.
@MainActor
@Suite("EditorFindModel Select All / search-in-selection (Slice 5c)")
struct EditorFindModelSelectionTests {
    // MARK: - Select All Matches

    @Test("selectionSetForAllMatches is nil when there are no matches")
    func selectionSetForAllMatchesIsNilWithNoMatches() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.selectionSetForAllMatches == nil)
    }

    @Test("selectionSetForAllMatches contains every match's own range")
    func selectionSetForAllMatchesContainsEveryMatch() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        let selection = model.selectionSetForAllMatches
        #expect(selection?.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
            NSRange(location: 16, length: 3),
        ])
    }

    @Test("selectionSetForAllMatches makes the current match the primary selection")
    func selectionSetForAllMatchesMakesCurrentMatchPrimary() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)
        model.findNext() // now at index 1, location 8

        let selection = model.selectionSetForAllMatches
        #expect(selection?.primaryRange == NSRange(location: 8, length: 3))
    }

    @Test("selectionSetForAllMatches defaults to the first match as primary when there is no current match")
    func selectionSetForAllMatchesDefaultsToFirstMatchWhenNoCurrentIndex() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        #expect(model.currentIndex == nil)
        model.query = "cat"
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        let selection = model.selectionSetForAllMatches
        #expect(selection?.primaryRange == NSRange(location: 0, length: 3))
    }

    @Test("selectionSetForAllMatches works correctly for a single match")
    func selectionSetForAllMatchesWorksForASingleMatch() async {
        let model = EditorFindModel(query: "dog")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        let selection = model.selectionSetForAllMatches
        #expect(selection?.count == 1)
        #expect(selection?.ranges == [NSRange(location: 8, length: 3)])
    }

    // MARK: - Search in selection only

    @Test("searchesSelectionOnly with no selection falls back to the whole document")
    func searchesSelectionOnlyWithNoSelectionSearchesWholeDocument() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "cat", options: options)

        await model.updateMatches(in: "cat and cat", selection: nil, preferringLocationNear: 0)

        #expect(model.matchCount == 2)
    }

    @Test("searchesSelectionOnly with a zero-length caret (not a real selection) falls back to the whole document")
    func searchesSelectionOnlyWithACaretSearchesWholeDocument() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "cat", options: options)

        await model.updateMatches(
            in: "cat and cat",
            selection: NSRange(location: 4, length: 0),
            preferringLocationNear: 0
        )

        #expect(model.matchCount == 2)
    }

    @Test("searchesSelectionOnly with a real selection only returns matches inside it")
    func searchesSelectionOnlyReturnsOnlyMatchesInsideTheSelection() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "cat", options: options)
        // "cat and cat and cat" -- matches at 0, 8, 16. Selection [4, 15)
        // is "and cat and" -- it fully contains the match at 8, but neither
        // the match at 0 (starts before the selection) nor at 16 (starts
        // after it).
        let selection = NSRange(location: 4, length: 11)

        await model.updateMatches(in: "cat and cat and cat", selection: selection, preferringLocationNear: 0)

        #expect(model.matchCount == 1)
        #expect(model.currentMatch?.range == NSRange(location: 8, length: 3))
    }

    @Test("searchesSelectionOnly's returned match ranges are offset back to full-document coordinates")
    func searchesSelectionOnlyOffsetsMatchRangesToDocumentCoordinates() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "dog", options: options)
        let text = "cat and dog and dog"
        // Selection covers everything from the first "dog" onward.
        let selection = NSRange(location: 8, length: text.utf16.count - 8)

        await model.updateMatches(in: text, selection: selection, preferringLocationNear: 0)

        #expect(model.matchCount == 2)
        #expect(model.currentMatch?.range == NSRange(location: 8, length: 3))
        model.findNext()
        #expect(model.currentMatch?.range == NSRange(location: 16, length: 3))
    }

    @Test("searchesSelectionOnly false ignores the selection entirely, even when one is provided")
    func searchesSelectionOnlyFalseIgnoresTheSelection() async {
        let model = EditorFindModel(query: "cat") // isRegex/searchesSelectionOnly both default false
        let selection = NSRange(location: 4, length: 3) // covers only "and", not either "cat"

        await model.updateMatches(in: "cat and cat", selection: selection, preferringLocationNear: 0)

        #expect(model.matchCount == 2)
    }

    @Test("a selection with no matches inside it produces zero matches, not a fallback to the whole document")
    func selectionWithNoMatchesInsideProducesZeroMatches() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "cat", options: options)
        let selection = NSRange(location: 4, length: 3) // "and" -- no "cat" in here

        await model.updateMatches(in: "cat and cat", selection: selection, preferringLocationNear: 0)

        #expect(model.matchCount == 0)
    }

    @Test("a selection range that extends past the live text length is clamped, not a crash")
    func selectionPastLiveTextLengthIsClamped() async {
        var options = SearchOptions()
        options.searchesSelectionOnly = true
        let model = EditorFindModel(query: "cat", options: options)
        // A stale selection referring to a since-shortened document.
        let selection = NSRange(location: 0, length: 1000)

        await model.updateMatches(in: "cat and cat", selection: selection, preferringLocationNear: 0)

        #expect(model.matchCount == 2)
    }
}
