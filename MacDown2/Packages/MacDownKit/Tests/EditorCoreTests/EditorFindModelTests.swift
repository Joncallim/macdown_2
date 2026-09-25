@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// EPIC-22 §6.14, Slice 5a — pure-logic tests for `EditorFindModel`,
/// entirely independent of `NSTextView`/SwiftUI.
@MainActor
@Suite("EditorFindModel (Slice 5a)")
struct EditorFindModelTests {
    // MARK: - Basic matching

    @Test("updateMatches computes literal matches and selects the nearest one")
    func updateMatchesComputesLiteralMatches() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        #expect(model.matchCount == 3)
        #expect(model.currentIndex == 0)
        #expect(model.currentMatch?.range == NSRange(location: 0, length: 3))
    }

    @Test("an empty query produces no matches and no current index")
    func emptyQueryProducesNoMatches() {
        let model = EditorFindModel(query: "")
        model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentIndex == nil)
        #expect(model.currentMatch == nil)
    }

    @Test("a query with no occurrences produces no matches")
    func noOccurrencesProducesNoMatches() {
        let model = EditorFindModel(query: "zzz")
        model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentMatch == nil)
    }

    // MARK: - Anchor-based nearest-match selection

    @Test("updateMatches selects the first match AT OR AFTER the anchor, not always the first overall")
    func updateMatchesSelectsNearestMatchAfterAnchor() {
        let model = EditorFindModel(query: "cat")
        // "cat and cat and cat" -- matches at 0, 8, 16. An anchor of 9 falls
        // strictly between the matches at 8 and 16, so the nearest match AT
        // OR AFTER it is the one at 16 (index 2), not the one before it.
        model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 9)

        #expect(model.currentIndex == 2)
        #expect(model.currentMatch?.range.location == 16)
    }

    @Test("updateMatches wraps to the first match when the anchor is past every match")
    func updateMatchesWrapsToFirstMatchWhenAnchorIsPastAll() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat", preferringLocationNear: 100)

        #expect(model.currentIndex == 0)
    }

    @Test("a nil anchor defaults to the first match")
    func nilAnchorDefaultsToFirstMatch() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat", preferringLocationNear: nil)

        #expect(model.currentIndex == 0)
    }

    // MARK: - Find Next / Previous

    @Test("findNext cycles forward through matches")
    func findNextCyclesForward() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        #expect(model.findNext()?.range.location == 8)
        #expect(model.findNext()?.range.location == 16)
    }

    @Test("findNext wraps to the first match when options.wraps is true (the default)")
    func findNextWrapsWhenEnabled() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        _ = model.findNext() // now at index 1 (the last match)

        let wrapped = model.findNext()

        #expect(wrapped?.range.location == 0)
        #expect(model.currentIndex == 0)
    }

    @Test("findNext stays at the last match when options.wraps is false")
    func findNextStaysPutWhenWrapDisabled() {
        var options = SearchOptions()
        options.wraps = false
        let model = EditorFindModel(query: "cat", options: options)
        model.updateMatches(in: "cat and cat", preferringLocationNear: 0)
        _ = model.findNext() // now at the last match (index 1)

        let stillLast = model.findNext()

        #expect(stillLast?.range.location == 8) // unchanged -- did not wrap ("cat and cat"'s 2nd "cat" starts at 8)
        #expect(model.currentIndex == 1)
    }

    @Test("findPrevious cycles backward and wraps to the last match")
    func findPreviousCyclesBackwardAndWraps() {
        let model = EditorFindModel(query: "cat")
        model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0) // starts at index 0

        let wrapped = model.findPrevious()

        #expect(wrapped?.range.location == 16) // wrapped to the last match
    }

    @Test("findPrevious stays at the first match when options.wraps is false")
    func findPreviousStaysPutWhenWrapDisabled() {
        var options = SearchOptions()
        options.wraps = false
        let model = EditorFindModel(query: "cat", options: options)
        model.updateMatches(in: "cat and cat", preferringLocationNear: 0) // starts at index 0

        let stillFirst = model.findPrevious()

        #expect(stillFirst?.range.location == 0)
        #expect(model.currentIndex == 0)
    }

    @Test("re-running updateMatches after a query change re-resolves currentIndex from scratch")
    func updateMatchesReResolvesAfterQueryChange() {
        let model = EditorFindModel(query: "dog")
        model.updateMatches(in: "cat and dog", preferringLocationNear: 0)
        #expect(model.matchCount == 1)

        model.query = "cat"
        model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.matchCount == 1)
        #expect(model.currentMatch?.range.location == 0)
    }

    @Test("findNext/findPrevious on an empty match list return nil and clear the current index")
    func findNextOnEmptyMatchListReturnsNil() {
        let model = EditorFindModel(query: "zzz")
        model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.findNext() == nil)
        #expect(model.findPrevious() == nil)
        #expect(model.currentIndex == nil)
    }

    // MARK: - Regex errors

    @Test("an invalid regex clears matches and populates error")
    func invalidRegexClearsMatchesAndPopulatesError() {
        var options = SearchOptions()
        options.isRegex = true
        let model = EditorFindModel(query: "(unclosed", options: options)
        model.updateMatches(in: "some text", preferringLocationNear: 0)

        #expect(model.matchCount == 0)
        #expect(model.currentMatch == nil)
        #expect(model.error != nil)
    }

    @Test("a valid regex query matches and clears any prior error")
    func validRegexClearsPriorError() {
        var options = SearchOptions()
        options.isRegex = true
        let model = EditorFindModel(query: "(unclosed", options: options)
        model.updateMatches(in: "some text", preferringLocationNear: 0)
        #expect(model.error != nil)

        model.query = "\\d+"
        model.updateMatches(in: "abc 123 def", preferringLocationNear: 0)

        #expect(model.error == nil)
        #expect(model.matchCount == 1)
        #expect(model.currentMatch?.range == NSRange(location: 4, length: 3))
    }

    // MARK: - Options round-trip

    @Test("case-sensitive and whole-word options are honored via TextSearchEngine")
    func caseSensitiveAndWholeWordOptionsAreHonored() {
        var options = SearchOptions()
        options.isCaseSensitive = true
        options.isWholeWord = true
        let model = EditorFindModel(query: "Cat", options: options)
        model.updateMatches(in: "Cat cats CAT Cat", preferringLocationNear: 0)

        // Only the two exact, whole-word, case-sensitive "Cat" occurrences.
        #expect(model.matchCount == 2)
    }
}
