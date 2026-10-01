@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// #183 F03 — "In Selection" keeps the domain it was established with, through
/// highlight-driven selection changes and through Replace edits.
@MainActor
@Suite("EditorFindModel retained search domain (#183 F03)")
struct EditorFindModelSearchDomainTests {
    private func model(options: SearchOptions = SearchOptions(searchesSelectionOnly: true)) -> EditorFindModel {
        let model = EditorFindModel(query: "cat")
        model.options = options
        return model
    }

    private func starts(_ model: EditorFindModel) -> [Int] {
        model.matches.map(\.range.location)
    }

    @Test func theDomainSurvivesRefreshesThatCarryNoSelection() async {
        let model = model()
        let text = "cat cat cat"
        await model.updateMatches(in: text, selection: NSRange(location: 0, length: 7), preferringLocationNear: 0)
        #expect(starts(model) == [0, 4])

        // The editor's live selection is now the highlighted match / a caret;
        // refreshes pass no selection and must not narrow or widen the domain.
        await model.updateMatches(in: text, preferringLocationNear: 4)
        #expect(starts(model) == [0, 4])
        #expect(model.searchDomain == NSRange(location: 0, length: 7))
    }

    @Test func replacingInsideTheDomainDoesNotAdmitMatchesOutsideIt() async throws {
        let model = model()
        var text = "cat cat cat"
        await model.updateMatches(in: text, selection: NSRange(location: 0, length: 7), preferringLocationNear: 0)
        let transaction = try #require(model.replaceCurrentTransaction(with: "dog"))
        model.remapSearchDomain(through: transaction)
        text = try #require(LineTransformTestSupport.applied(transaction, to: text)?.text)

        await model.updateMatches(in: text, preferringLocationNear: 4)

        #expect(text == "dog cat cat")
        #expect(starts(model) == [4])
    }

    @Test func aShorterReplacementShrinksTheDomainWithIt() async throws {
        let model = model()
        var text = "cat cat cat"
        await model.updateMatches(in: text, selection: NSRange(location: 0, length: 7), preferringLocationNear: 0)
        let transaction = try #require(model.replaceAllTransaction(with: "x"))
        model.remapSearchDomain(through: transaction)
        text = try #require(LineTransformTestSupport.applied(transaction, to: text)?.text)

        #expect(text == "x x cat")
        #expect(model.searchDomain == NSRange(location: 0, length: 3))
    }

    @Test func aReplacementBeforeTheDomainShiftsIt() async {
        let model = model()
        let text = "cat xx cat"
        await model.updateMatches(in: text, selection: NSRange(location: 4, length: 6), preferringLocationNear: 0)
        let transaction = EditorEditTransaction(
            replacements: [TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "tiger")],
            undoActionName: "Replace",
            resultingSelection: nil
        )

        model.remapSearchDomain(through: transaction)

        #expect(model.searchDomain == NSRange(location: 6, length: 6))
    }

    @Test func turningTheOptionOffForgetsTheDomainAndSearchesEverything() async {
        let model = model()
        await model.updateMatches(
            in: "cat cat cat",
            selection: NSRange(location: 0, length: 7),
            preferringLocationNear: 0
        )
        model.options.searchesSelectionOnly = false

        await model.updateMatches(in: "cat cat cat", preferringLocationNear: 0)

        #expect(model.searchDomain == nil)
        #expect(starts(model) == [0, 4, 8])
    }

    @Test func aCaretOnlySelectionFallsBackToTheWholeDocumentAndClearDropsTheDomain() async {
        let model = model()
        await model.updateMatches(
            in: "cat cat cat",
            selection: NSRange(location: 2, length: 0),
            preferringLocationNear: 0
        )
        #expect(starts(model) == [0, 4, 8])
        #expect(model.searchDomain == nil)

        await model.updateMatches(
            in: "cat cat cat",
            selection: NSRange(location: 0, length: 3),
            preferringLocationNear: 0
        )
        model.clearSearchDomain()
        #expect(model.searchDomain == nil)
    }
}
