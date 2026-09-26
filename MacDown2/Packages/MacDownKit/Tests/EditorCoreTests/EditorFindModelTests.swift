@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// EPIC-22 §6.14, Slice 5a — pure-logic tests for `EditorFindModel`,
/// entirely independent of `NSTextView`/SwiftUI. `updateMatches(in:)` runs
/// its actual search off-main (a hostile PR review of this slice found the
/// original synchronous, main-actor version froze the whole app on a
/// catastrophic-backtracking regex — see that method's own doc comment), so
/// every test that calls it is `async`.
@MainActor
@Suite("EditorFindModel (Slice 5a)")
struct EditorFindModelTests {
    // MARK: - Basic matching

    @Test("updateMatches computes literal matches and selects the nearest one")
    func updateMatchesComputesLiteralMatches() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        #expect(model.matchCount == 3)
        #expect(model.currentIndex == 0)
        #expect(model.currentMatch?.range == NSRange(location: 0, length: 3))
    }

    @Test("an empty query produces no matches and no current index")
    func emptyQueryProducesNoMatches() async {
        let model = EditorFindModel(query: "")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentIndex == nil)
        #expect(model.currentMatch == nil)
    }

    @Test("a query with no occurrences produces no matches")
    func noOccurrencesProducesNoMatches() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentMatch == nil)
    }

    // MARK: - Anchor-based nearest-match selection

    @Test("updateMatches selects the first match AT OR AFTER the anchor, not always the first overall")
    func updateMatchesSelectsNearestMatchAfterAnchor() async {
        let model = EditorFindModel(query: "cat")
        // "cat and cat and cat" -- matches at 0, 8, 16. An anchor of 9 falls
        // strictly between the matches at 8 and 16, so the nearest match AT
        // OR AFTER it is the one at 16 (index 2), not the one before it.
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 9)

        #expect(model.currentIndex == 2)
        #expect(model.currentMatch?.range.location == 16)
    }

    @Test("updateMatches wraps to the first match when the anchor is past every match")
    func updateMatchesWrapsToFirstMatchWhenAnchorIsPastAll() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 100)

        #expect(model.currentIndex == 0)
    }

    @Test("a nil anchor defaults to the first match")
    func nilAnchorDefaultsToFirstMatch() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: nil)

        #expect(model.currentIndex == 0)
    }

    // MARK: - Find Next / Previous

    @Test("findNext cycles forward through matches")
    func findNextCyclesForward() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        #expect(model.findNext()?.range.location == 8)
        #expect(model.findNext()?.range.location == 16)
    }

    @Test("findNext wraps to the first match when options.wraps is true (the default)")
    func findNextWrapsWhenEnabled() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        _ = model.findNext() // now at index 1 (the last match)

        let wrapped = model.findNext()

        #expect(wrapped?.range.location == 0)
        #expect(model.currentIndex == 0)
    }

    @Test("findNext stays at the last match when options.wraps is false")
    func findNextStaysPutWhenWrapDisabled() async {
        var options = SearchOptions()
        options.wraps = false
        let model = EditorFindModel(query: "cat", options: options)
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        _ = model.findNext() // now at the last match (index 1)

        let stillLast = model.findNext()

        #expect(stillLast?.range.location == 8) // unchanged -- did not wrap ("cat and cat"'s 2nd "cat" starts at 8)
        #expect(model.currentIndex == 1)
    }

    @Test("findPrevious cycles backward and wraps to the last match")
    func findPreviousCyclesBackwardAndWraps() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0) // starts at index 0

        let wrapped = model.findPrevious()

        #expect(wrapped?.range.location == 16) // wrapped to the last match
    }

    @Test("findPrevious stays at the first match when options.wraps is false")
    func findPreviousStaysPutWhenWrapDisabled() async {
        var options = SearchOptions()
        options.wraps = false
        let model = EditorFindModel(query: "cat", options: options)
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0) // starts at index 0

        let stillFirst = model.findPrevious()

        #expect(stillFirst?.range.location == 0)
        #expect(model.currentIndex == 0)
    }

    @Test("re-running updateMatches after a query change re-resolves currentIndex from scratch")
    func updateMatchesReResolvesAfterQueryChange() async {
        let model = EditorFindModel(query: "dog")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)
        #expect(model.matchCount == 1)

        model.query = "cat"
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.matchCount == 1)
        #expect(model.currentMatch?.range.location == 0)
    }

    @Test("findNext/findPrevious on an empty match list return nil and clear the current index")
    func findNextOnEmptyMatchListReturnsNil() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.findNext() == nil)
        #expect(model.findPrevious() == nil)
        #expect(model.currentIndex == nil)
    }

    // MARK: - Regex errors

    @Test("an invalid regex clears matches and populates error")
    func invalidRegexClearsMatchesAndPopulatesError() async {
        var options = SearchOptions()
        options.isRegex = true
        let model = EditorFindModel(query: "(unclosed", options: options)
        await model.updateMatches(in: "some text", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentMatch == nil)
        #expect(model.error != nil)
    }

    @Test("a valid regex query matches and clears any prior error")
    func validRegexClearsPriorError() async {
        var options = SearchOptions()
        options.isRegex = true
        let model = EditorFindModel(query: "(unclosed", options: options)
        await model.updateMatches(in: "some text", preferringLocationNear: 0)
        #expect(model.error != nil)

        model.query = "\\d+"
        await model.updateMatches(in: "abc 123 def", preferringLocationNear: 0)

        #expect(model.error == nil)
        #expect(model.matchCount == 1)
        #expect(model.currentMatch?.range == NSRange(location: 4, length: 3))
    }

    // MARK: - Options round-trip

    @Test("case-sensitive and whole-word options are honored via TextSearchEngine")
    func caseSensitiveAndWholeWordOptionsAreHonored() async {
        var options = SearchOptions()
        options.isCaseSensitive = true
        options.isWholeWord = true
        let model = EditorFindModel(query: "Cat", options: options)
        await model.updateMatches(in: "Cat cats CAT Cat", preferringLocationNear: 0)

        // Only the two exact, whole-word, case-sensitive "Cat" occurrences.
        #expect(model.matchCount == 2)
    }

    // MARK: - Off-main execution (post-review fix)

    @Test("updateMatches leaves isSearching false once it has completed")
    func updateMatchesLeavesSearchingFalseWhenDone() async {
        let model = EditorFindModel(query: "cat")

        let committed = await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        #expect(committed)
        #expect(model.isSearching == false)
    }

    @Test("a sequence of updateMatches calls always ends on the most recent call's own result")
    func sequentialUpdatesEndOnTheLatestResult() async {
        // `searchGeneration`'s own job (discarding a superseded call's
        // result when TWO calls genuinely race, e.g. fast typing or a slow
        // regex still in flight) is deliberately NOT tested here by forcing
        // an actual race: an `async let`/unstructured-`Task` race between
        // two MainActor-isolated calls has no language-guaranteed ordering
        // for which one's synchronous prefix (and therefore which one
        // captures the SMALLER generation) runs first, which would make
        // such a test's pass/fail depend on scheduler behavior rather than
        // the code under test -- exactly the "flaky, not incorrect" failure
        // mode this codebase has already been burned by once (see
        // `planning/epic-22-implementation.md`'s own account of a similar
        // `async let`-race test rewritten for `WorkspaceFileIndex`). What
        // IS meaningfully verified, deterministically, is the property the
        // generation guard exists to preserve: repeatedly calling
        // `updateMatches` never leaves the model on anything other than
        // its OWN most recent call's result.
        let model = EditorFindModel(query: "cat")

        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)
        #expect(model.matchCount == 1)

        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        #expect(model.matchCount == 2)

        await model.updateMatches(in: "dog only", preferringLocationNear: 0)
        #expect(model.matchCount == 0)
    }
}
