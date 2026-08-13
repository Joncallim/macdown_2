@testable import EditorCore
import Foundation
import Testing

@Suite("Editing assists — Return continuation")
struct EditingAssistNewlineTests {
    private let support = EditingAssistTestSupport.self

    private func pressReturn(in text: String, at location: Int) -> EditingAssistOutcome {
        support.outcome(for: .insertNewline, in: text, selection: NSRange(location: location, length: 0))
    }

    @Test("unordered list markers continue unchanged")
    func unorderedListsContinue() {
        for marker in ["-", "+", "*"] {
            let outcome = pressReturn(in: "\(marker) item", at: 6)
            let result = support.applied(outcome, to: "\(marker) item")
            #expect(result?.text == "\(marker) item\n\(marker) ", "marker \(marker)")
            #expect(result?.selection == NSRange(location: 9, length: 0), "marker \(marker)")
        }
    }

    @Test("ordered list auto-increments")
    func orderedListsIncrement() {
        let outcome = pressReturn(in: "1. item", at: 7)
        let result = support.applied(outcome, to: "1. item")
        #expect(result?.text == "1. item\n2. ")
    }

    @Test("multi-digit increment")
    func multiDigitIncrement() {
        let outcome = pressReturn(in: "9. item", at: 7)
        let result = support.applied(outcome, to: "9. item")
        #expect(result?.text == "9. item\n10. ")
    }

    @Test("leading-zero increment preserves width")
    func leadingZeroPreservesWidth() {
        let outcome = pressReturn(in: "009. item", at: 9)
        let result = support.applied(outcome, to: "009. item")
        #expect(result?.text == "009. item\n010. ")
    }

    @Test("huge digit string repeats safely instead of trapping")
    func overflowDigitsRepeatSafely() {
        let huge = "99999999999999999999"
        let outcome = pressReturn(in: "\(huge). item", at: huge.utf16.count + 7)
        let result = support.applied(outcome, to: "\(huge). item")
        #expect(result?.text == "\(huge). item\n\(huge). ")

        // Int.max itself must not overflow when incremented.
        let max = "9223372036854775807"
        let maxOutcome = pressReturn(in: "\(max). item", at: max.utf16.count + 7)
        let maxResult = support.applied(maxOutcome, to: "\(max). item")
        #expect(maxResult?.text == "\(max). item\n\(max). ")
    }

    @Test("increment-disabled ordered list repeats exact digits")
    func incrementDisabledRepeatsDigits() {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.autoIncrementOrderedLists = false
        let outcome = support.outcome(
            for: .insertNewline,
            in: "1. item",
            selection: NSRange(location: 7, length: 0),
            configuration: configuration
        )
        let result = support.applied(outcome, to: "1. item")
        #expect(result?.text == "1. item\n1. ")
    }

    @Test("task lists continue as unchecked")
    func taskListsContinueUnchecked() {
        for marker in ["[ ]", "[x]", "[X]"] {
            let outcome = pressReturn(in: "- \(marker) done", at: 10)
            let result = support.applied(outcome, to: "- \(marker) done")
            #expect(result?.text == "- \(marker) done\n- [ ] ", "marker \(marker)")
        }
    }

    @Test("blockquote spelling and spacing preserved")
    func blockquoteContinues() {
        let outcome = pressReturn(in: "> quote", at: 7)
        let result = support.applied(outcome, to: "> quote")
        #expect(result?.text == "> quote\n> ")

        let tight = pressReturn(in: ">quote", at: 6)
        let tightResult = support.applied(tight, to: ">quote")
        #expect(tightResult?.text == ">quote\n>")
    }

    @Test("nested quotes preserved")
    func nestedQuotesContinue() {
        let outcome = pressReturn(in: "> > nested", at: 10)
        let result = support.applied(outcome, to: "> > nested")
        #expect(result?.text == "> > nested\n> > ")
    }

    @Test("composed quote plus list continues")
    func quotePlusListContinues() {
        let outcome = pressReturn(in: "> - item", at: 8)
        let result = support.applied(outcome, to: "> - item")
        #expect(result?.text == "> - item\n> - ")
    }

    @Test("composed quote plus task continues")
    func quotePlusTaskContinues() {
        let outcome = pressReturn(in: "> - [x] done", at: 12)
        let result = support.applied(outcome, to: "> - [x] done")
        #expect(result?.text == "> - [x] done\n> - [ ] ")
    }

    @Test("indentation-only content continues indent")
    func indentedContentContinues() {
        let outcome = pressReturn(in: "  indented", at: 10)
        let result = support.applied(outcome, to: "  indented")
        #expect(result?.text == "  indented\n  ")
    }

    @Test("plain line passes through")
    func plainLinePassesThrough() {
        #expect(pressReturn(in: "plain", at: 5) == .passthrough)
    }

    @Test("selection present passes through")
    func selectionPassesThrough() {
        let outcome = support.outcome(
            for: .insertNewline,
            in: "- item",
            selection: NSRange(location: 0, length: 4)
        )
        #expect(outcome == .passthrough)
    }

    @Test("empty list exits the list")
    func emptyListTerminates() {
        let outcome = pressReturn(in: "- ", at: 2)
        let result = support.applied(outcome, to: "- ")
        #expect(result?.text == "\n")
        #expect(result?.selection == NSRange(location: 1, length: 0))
    }

    @Test("empty task exits the list")
    func emptyTaskTerminates() {
        let outcome = pressReturn(in: "- [ ] ", at: 6)
        let result = support.applied(outcome, to: "- [ ] ")
        #expect(result?.text == "\n")
        #expect(result?.selection == NSRange(location: 1, length: 0))
    }

    @Test("empty indented list exits to indentation")
    func emptyIndentedListTerminates() {
        let outcome = pressReturn(in: "  - ", at: 4)
        let result = support.applied(outcome, to: "  - ")
        #expect(result?.text == "\n  ")
        #expect(result?.selection == NSRange(location: 3, length: 0))
    }

    @Test("empty list inside quote removes marker but keeps quote")
    func emptyListInQuoteKeepsQuote() {
        let outcome = pressReturn(in: "> - ", at: 4)
        let result = support.applied(outcome, to: "> - ")
        #expect(result?.text == "\n> ")
        #expect(result?.selection == NSRange(location: 3, length: 0))
    }

    @Test("empty quote exits the quote")
    func emptyQuoteTerminates() {
        let outcome = pressReturn(in: "> ", at: 2)
        let result = support.applied(outcome, to: "> ")
        #expect(result?.text == "\n")
        #expect(result?.selection == NSRange(location: 1, length: 0))
    }

    @Test("whitespace-only line without construct gets native newline")
    func whitespaceOnlyLinePassesThrough() {
        #expect(pressReturn(in: "   ", at: 3) == .passthrough)
        #expect(pressReturn(in: "", at: 0) == .passthrough)
    }

    @Test("mid-line Return preserves the tail exactly once")
    func midLineReturnPreservesTail() {
        let outcome = pressReturn(in: "- item", at: 4)
        let result = support.applied(outcome, to: "- item")
        #expect(result?.text == "- it\n- em")
        #expect(result?.selection == NSRange(location: 7, length: 0))
    }

    @Test("existing matching next prefix is not duplicated")
    func existingNextPrefixNotDuplicated() {
        let text = "- item\n- next"
        let outcome = pressReturn(in: text, at: 6)
        let result = support.applied(outcome, to: text)
        // The prefix is already present on the next line: only the separator
        // is inserted, exactly as native Return would split.
        #expect(result?.text == "- item\n\n- next")
        #expect(result?.selection == NSRange(location: 7, length: 0))
    }

    @Test("different next marker still inserts the continuation")
    func differentNextMarkerInsertsContinuation() {
        let text = "- item\n4. next"
        let outcome = pressReturn(in: text, at: 6)
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "- item\n- \n4. next")
    }

    @Test("CRLF fixture preserves CRLF without leaking a literal carriage return")
    func crlfFixturePreservesSeparator() {
        let text = "a\r\n- item\r\nnext"
        let outcome = pressReturn(in: text, at: 9)
        let result = support.applied(outcome, to: text)
        // The caret sits before the line's own "\r\n"; the inserted separator
        // is CRLF and the original tail (including its "\r\n") is preserved.
        #expect(result?.text == "a\r\n- item\r\n- \r\nnext")
        #expect(result?.text.contains("\r- ") == false)
    }

    @Test("disabled configuration passes every action family through")
    func disabledConfigurationPassesThrough() {
        let disabled = EditingAssistConfiguration.disabled
        #expect(support.outcome(
            for: .insertNewline,
            in: "- item",
            selection: NSRange(location: 7, length: 0),
            configuration: disabled
        ) == .passthrough)
        #expect(support.outcome(
            for: .insertTab,
            in: "x",
            selection: NSRange(location: 1, length: 0),
            configuration: disabled
        ) == .passthrough)
        #expect(support.outcome(
            for: .insertBacktab,
            in: "  x",
            selection: NSRange(location: 2, length: 0),
            configuration: disabled
        ) == .passthrough)
        #expect(support.outcome(
            for: .deleteBackward,
            in: "()",
            selection: NSRange(location: 1, length: 0),
            configuration: disabled
        ) == .passthrough)
        #expect(support.outcome(
            for: .smartHome,
            in: "  x",
            selection: NSRange(location: 3, length: 0),
            configuration: disabled
        ) == .passthrough)
        #expect(support.outcome(
            for: .markdownCommand(.bold),
            in: "x",
            selection: NSRange(location: 0, length: 1),
            configuration: disabled
        ) == .passthrough)
        #expect(support.type("(", in: " ", at: 0, configuration: disabled) == .passthrough)
    }
}
