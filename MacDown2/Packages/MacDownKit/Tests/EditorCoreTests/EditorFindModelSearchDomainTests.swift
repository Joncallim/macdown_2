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

    /// What the editor reports for a transaction: one edit per range, highest
    /// location first (each valid in turn).
    private func feed(_ model: EditorFindModel, _ transaction: EditorEditTransaction) {
        for replacement in transaction.replacements.sorted(by: { $0.range.location > $1.range.location }) {
            model.noteTextChange(.edit(
                range: replacement.range,
                replacementLength: (replacement.replacementText as NSString).length
            ))
        }
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
        feed(model, transaction)
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
        feed(model, transaction)
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

        feed(model, transaction)

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

    // MARK: - Edits of any origin keep the domain in step

    @Test func editsBeforeInsideAndAfterTheDomainAdjustItAsExpected() async {
        let model = model()
        await model.updateMatches(
            in: "0123456789",
            selection: NSRange(location: 4, length: 4),
            preferringLocationNear: 0
        )

        model.noteTextChange(.edit(range: NSRange(location: 0, length: 2), replacementLength: 5)) // before: +3
        #expect(model.searchDomain == NSRange(location: 7, length: 4))

        model.noteTextChange(.edit(range: NSRange(location: 8, length: 1), replacementLength: 3)) // inside: +2
        #expect(model.searchDomain == NSRange(location: 7, length: 6))

        model.noteTextChange(.edit(
            range: NSRange(location: 13, length: 0),
            replacementLength: 9
        )) // at the end: unchanged
        #expect(model.searchDomain == NSRange(location: 7, length: 6))

        model.noteTextChange(.edit(range: NSRange(location: 20, length: 1), replacementLength: 0)) // after: unchanged
        #expect(model.searchDomain == NSRange(location: 7, length: 6))
    }

    @Test func anEditStraddlingABoundaryCoversTheNewText() async {
        let model = model()
        await model.updateMatches(
            in: "0123456789",
            selection: NSRange(location: 4, length: 4),
            preferringLocationNear: 0
        )

        model.noteTextChange(.edit(range: NSRange(location: 2, length: 4), replacementLength: 1)) // straddles the start
        #expect(model.searchDomain == NSRange(location: 2, length: 3))
    }

    @Test func aChangeWithoutGeometryLosesTheScopeAndMatchesNothingUntilItIsReestablished() async {
        let model = model()
        let text = "cat cat cat"
        await model.updateMatches(in: text, selection: NSRange(location: 0, length: 7), preferringLocationNear: 0)
        #expect(starts(model) == [0, 4])

        model.noteTextChange(.untracked)
        await model.updateMatches(in: text, preferringLocationNear: 0)
        #expect(model.searchDomainLost)
        #expect(starts(model).isEmpty)

        await model.updateMatches(in: text, selection: NSRange(location: 4, length: 7), preferringLocationNear: 0)
        #expect(!model.searchDomainLost)
        #expect(starts(model) == [4, 8])
    }

    @Test func changesAreIgnoredWhileInSelectionIsOff() async {
        let model = model(options: SearchOptions())
        await model.updateMatches(in: "cat cat", preferringLocationNear: 0)

        model.noteTextChange(.untracked)

        #expect(!model.searchDomainLost)
        #expect(model.searchDomain == nil)
    }

    // MARK: - Through the real text system (the editor's own edit stream)

    @Test func theDomainSurvivesConvertLineEndingsAndIsLostOnUndo() async {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "a\r\nfoo\r\nfoo\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        _ = coordinator
        let model = EditorFindModel(query: "foo")
        model.options = SearchOptions(searchesSelectionOnly: true)
        await model.updateMatches(
            in: system.text,
            selection: NSRange(location: 3, length: 8),
            preferringLocationNear: 0
        )
        #expect(starts(model) == [3, 8])
        system.textChangeObserver = { [weak model] change in model?.noteTextChange(change) }

        #expect(system.convertLineEndings(to: .lineFeed))
        await model.updateMatches(in: system.text, preferringLocationNear: 0)
        #expect(system.text == "a\nfoo\nfoo\nb")
        #expect(starts(model) == [2, 6])

        system.undoManager.undo()
        await model.updateMatches(in: system.text, preferringLocationNear: 0)
        #expect(model.searchDomainLost)
        #expect(starts(model).isEmpty)
    }
}
