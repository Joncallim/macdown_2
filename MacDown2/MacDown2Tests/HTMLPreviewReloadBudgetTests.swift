@testable import MacDown2
import Testing

/// A page that kills the WebContent process every time must not be reloaded in a tight crash loop.
struct HTMLPreviewReloadBudgetTests {
    @Test func aSecondTerminationForTheSameDocumentIsNotReloaded() {
        var budget = HTMLPreviewReloadBudget()

        let first = budget.consumeReload()
        let second = budget.consumeReload()
        let third = budget.consumeReload()

        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func aNewDocumentRestoresTheBudget() {
        var budget = HTMLPreviewReloadBudget()
        _ = budget.consumeReload()

        budget.documentChanged()
        let afterNewDocument = budget.consumeReload()

        #expect(afterNewDocument)
    }
}
