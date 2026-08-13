@testable import EditorCore
import Foundation
import Testing

extension EditingAssistNewlineTests {
    @Test("asterisk after nested quote prefix stays a list marker")
    func asteriskAfterQuotePrefixDoesNotPair() {
        let outcome = EditingAssistTestSupport.outcome(
            for: .replacement(range: NSRange(location: 2, length: 0), string: "*"),
            in: "> ",
            selection: NSRange(location: 2, length: 0)
        )
        #expect(outcome == .passthrough)
        let nested = EditingAssistTestSupport.outcome(
            for: .replacement(range: NSRange(location: 4, length: 0), string: "*"),
            in: "> > ",
            selection: NSRange(location: 4, length: 0)
        )
        #expect(nested == .passthrough)
    }

    @Test("termination checks content after the caret")
    func midLineConstructDoesNotTerminate() {
        let list = EditingAssistNewlineTests().pressReturnForReview(in: "- item", at: 2)
        #expect(EditingAssistTestSupport.applied(list, to: "- item")?.text == "- \n- item")
        let quote = EditingAssistNewlineTests().pressReturnForReview(in: "> quote", at: 2)
        #expect(EditingAssistTestSupport.applied(quote, to: "> quote")?.text == "> \n> quote")
    }

    @Test("prefix continuation can be disabled")
    func continuationFlagPassesThrough() {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.continuesMarkdownPrefixes = false
        let outcome = EditingAssistTestSupport.outcome(
            for: .insertNewline,
            in: "- item",
            selection: NSRange(location: 6, length: 0),
            configuration: configuration
        )
        #expect(outcome == .passthrough)
    }
}

private extension EditingAssistNewlineTests {
    func pressReturnForReview(in text: String, at location: Int) -> EditingAssistOutcome {
        EditingAssistTestSupport.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: location, length: 0)
        )
    }
}
