@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// EPIC-22 §6.14, Slice 5b — `EditorFindModel.replaceCurrentTransaction`/
/// `replaceAllTransaction`, entirely independent of `NSTextView`. Both
/// methods return a plain `EditorEditTransaction` for the caller to apply;
/// `LineTransformTestSupport.applied(_:to:)` (from `EditorLineTransformsTests.swift`,
/// same test target) simulates that application against a plain `String`
/// without needing a real mounted text view.
@MainActor
@Suite("EditorFindModel Replace/Replace All (Slice 5b)")
struct EditorFindModelReplaceTests {
    // MARK: - Replace (current match only)

    @Test("replaceCurrentTransaction is nil when there is no current match")
    func replaceCurrentIsNilWithNoCurrentMatch() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.replaceCurrentTransaction(with: "x") == nil)
    }

    @Test("replaceCurrentTransaction replaces only the current match, leaving the others untouched")
    func replaceCurrentReplacesOnlyTheCurrentMatch() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)
        model.findNext() // now at index 1, the middle "cat" (location 8)

        let transaction = model.replaceCurrentTransaction(with: "dog")
        let applied = LineTransformTestSupport.applied(transaction, to: "cat and cat and cat")

        #expect(applied?.text == "cat and dog and cat")
    }

    @Test("replaceCurrentTransaction's resulting caret lands right after the replacement text")
    func replaceCurrentCaretLandsAfterReplacement() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        let transaction = model.replaceCurrentTransaction(with: "elephant")
        let applied = LineTransformTestSupport.applied(transaction, to: "cat and dog")

        #expect(applied?.text == "elephant and dog")
        // "elephant" is 8 UTF-16 units, starting at 0 -> caret at 8.
        #expect(applied?.selection == NSRange(location: 8, length: 0))
    }

    @Test("replaceCurrentTransaction shrinks or grows correctly when the replacement's length differs")
    func replaceCurrentHandlesLengthChange() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "a cat sat", preferringLocationNear: 0)

        let transaction = model.replaceCurrentTransaction(with: "")
        let applied = LineTransformTestSupport.applied(transaction, to: "a cat sat")

        #expect(applied?.text == "a  sat")
        #expect(applied?.selection == NSRange(location: 2, length: 0))
    }

    // MARK: - Replace All

    @Test("replaceAllTransaction is nil when there are no matches")
    func replaceAllIsNilWithNoMatches() async {
        let model = EditorFindModel(query: "zzz")
        await model.updateMatches(in: "cat and dog", preferringLocationNear: 0)

        #expect(model.replaceAllTransaction(with: "x") == nil)
    }

    @Test("replaceAllTransaction replaces every match in a single transaction")
    func replaceAllReplacesEveryMatch() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat and cat", preferringLocationNear: 0)

        let transaction = model.replaceAllTransaction(with: "dog")

        #expect(transaction?.replacements.count == 3)
        let applied = LineTransformTestSupport.applied(transaction, to: "cat and cat and cat")
        #expect(applied?.text == "dog and dog and dog")
    }

    @Test("replaceAllTransaction is one undo group, not N -- a single EditorEditTransaction")
    func replaceAllIsOneTransactionNotN() async {
        // §4 invariant #10: "a multi-cursor edit affecting N ranges is one
        // undo step, not N." `EditorEditTransaction.apply(_:)` brackets its
        // whole `replacements` array in one `breakUndoCoalescing()` pair
        // regardless of count -- the only thing to verify at this level is
        // that Replace All builds exactly ONE transaction object covering
        // every match, never N separate ones for the caller to apply in a
        // loop.
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat cat cat cat cat", preferringLocationNear: 0)

        let transaction = model.replaceAllTransaction(with: "x")

        #expect(transaction?.replacements.count == 5)
    }

    @Test("replaceAllTransaction's resulting caret lands after the LAST (highest-offset) replacement")
    func replaceAllCaretLandsAfterTheLastReplacement() async {
        let model = EditorFindModel(query: "cat")
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        let transaction = model.replaceAllTransaction(with: "elephant")
        let applied = LineTransformTestSupport.applied(transaction, to: "cat and cat")

        #expect(applied?.text == "elephant and elephant")
        // "elephant and elephant" is 21 UTF-16 units long; the caret lands
        // at the very end, right after the second "elephant".
        #expect(applied?.selection == NSRange(location: 21, length: 0))
    }

    @Test("replaceAllTransaction handles length-changing replacements across multiple matches correctly")
    func replaceAllHandlesLengthChangeAcrossMultipleMatches() async {
        let model = EditorFindModel(query: "a")
        await model.updateMatches(in: "banana", preferringLocationNear: 0)
        #expect(model.matchCount == 3) // "b-a-n-a-n-a": "a" at 1, 3, 5

        let transaction = model.replaceAllTransaction(with: "XY")
        let applied = LineTransformTestSupport.applied(transaction, to: "banana")

        #expect(applied?.text == "bXYnXYnXY")
    }
}
