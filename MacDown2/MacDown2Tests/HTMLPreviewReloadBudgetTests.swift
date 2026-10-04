@testable import MacDown2
import Testing

/// A page that kills the WebContent process every time must not be reloaded in a tight crash loop.
struct HTMLPreviewReloadBudgetTests {
    @Test func aSecondTerminationWithoutASuccessfulLoadIsNotReloaded() {
        var budget = HTMLPreviewReloadBudget()

        let first = budget.consumeReload()
        let second = budget.consumeReload()
        let third = budget.consumeReload()

        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func aSuccessfulLoadRestoresTheBudget() {
        var budget = HTMLPreviewReloadBudget()
        _ = budget.consumeReload()

        budget.loadSucceeded()
        let afterSuccess = budget.consumeReload()

        #expect(afterSuccess)
    }
}
