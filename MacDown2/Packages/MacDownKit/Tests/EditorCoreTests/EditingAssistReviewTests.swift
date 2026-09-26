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

    @Test("with continuation disabled, an INDENTED Markdown line's own leading whitespace is not carried over either")
    func continuationFlagDisabledAlsoSuppressesIndentationCarrying() {
        // A regression an independent hostile review of EPIC-22 §6.11 Slice
        // 4a found: the sibling test above (`continuationFlagPassesThrough`)
        // uses a fixture with NO leading whitespace, so it kept passing even
        // when a real bug made Return on a Markdown document, with this
        // exact preference off, wrongly fall into the NEW general "maintain
        // indentation" behavior Slice 4a added for non-Markdown formats —
        // resurrecting indentation-carrying for exactly the users who used
        // this toggle ("Continue lists, quotes, and indentation on Return")
        // to turn it off. This fixture's leading four spaces are what
        // actually exercises that path.
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.continuesMarkdownPrefixes = false
        let text = "    - item"
        let outcome = EditingAssistTestSupport.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: configuration,
            profile: LanguageEditingProfileRegistry.profile(for: "markdown")
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
