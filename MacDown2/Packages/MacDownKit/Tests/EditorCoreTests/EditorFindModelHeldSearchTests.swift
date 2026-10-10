@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// Handoff regression 5 (#377): a search held across close, reopen and a new query must not authorise replacement,
/// reselect or republish highlights from the retired query's matches; and the search-in-selection boundary must
/// hold for replacements built from the result.
@MainActor
struct EditorFindModelHeldSearchTests {
    private func startHeldSearch(_ model: EditorFindModel, in text: String) async -> Task<Bool, Never> {
        let search = Task { await model.updateMatches(in: text) }
        while !model.isSearching {
            await Task.yield()
        }
        return search
    }

    @Test func aSearchHeldAcrossCloseReopenAndANewQueryNeverPublishesOrAuthorisesReplacement() async {
        let pathological = String(repeating: "a", count: 40) + "!"
        let live = "foo bar foo"
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        let held = await startHeldSearch(model, in: pathological)

        model.cancelPendingSearch() // Find closed while the search is in flight
        #expect(!model.isSearching)
        #expect(model.replaceAllTransaction(with: "X") == nil, "no stale match may authorise a replacement")

        // Reopened with a different query against the live document.
        model.options = SearchOptions()
        model.query = "foo"
        let published = await model.updateMatches(in: live)
        let heldPublished = await held.value

        #expect(published)
        #expect(!heldPublished, "the retired search must not publish")
        #expect(model.matches.map(\.range) == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        let transaction = model.replaceAllTransaction(with: "X")
        #expect(transaction?.replacements.map(\.range) == model.matches.map(\.range))
        #expect(model.matchesAreCurrent(forLiveText: live))
    }

    @Test func aCloseWithNoLaterSearchLeavesNothingToReplace() async {
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        let held = await startHeldSearch(model, in: String(repeating: "a", count: 40) + "!")

        model.cancelPendingSearch()
        let published = await held.value

        #expect(!published)
        #expect(model.matches.isEmpty)
        #expect(model.currentMatch == nil)
        #expect(model.replaceCurrentTransaction(with: "X") == nil)
        #expect(model.replaceAllTransaction(with: "X") == nil)
    }

    @Test func aSelectionOnlySearchReplacesOnlyMatchesInsideTheSelectedRange() async {
        let text = "foo foo foo foo"
        let selection = NSRange(location: 4, length: 7) // "foo foo"
        let model = EditorFindModel(query: "foo")
        model.options = SearchOptions(searchesSelectionOnly: true)
        await model.updateMatches(in: text, selection: selection)

        let transaction = model.replaceAllTransaction(with: "X")

        #expect(model.matches.map(\.range) == [NSRange(location: 4, length: 3), NSRange(location: 8, length: 3)])
        #expect(transaction?.replacements.map(\.range) == model.matches.map(\.range))
        for range in transaction?.replacements.map(\.range) ?? [] {
            #expect(NSLocationInRange(range.location, selection) && NSMaxRange(range) <= NSMaxRange(selection))
        }
        // A content change outside the matches still invalidates them for the live text.
        #expect(!model.matchesAreCurrent(forLiveText: "Foo foo foo foo"))
    }
}
