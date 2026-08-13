@testable import EditorCore
import Foundation
import Testing

@Suite("Editing assists — Tab / Shift-Tab indentation")
struct EditingAssistIndentationTests {
    private let support = EditingAssistTestSupport.self

    private func pressTab(
        in text: String,
        selection: NSRange,
        configuration: EditingAssistConfiguration = .markdownDefault
    ) -> EditingAssistOutcome {
        support.outcome(for: .insertTab, in: text, selection: selection, configuration: configuration)
    }

    private func pressBacktab(
        in text: String,
        selection: NSRange,
        configuration: EditingAssistConfiguration = .markdownDefault
    ) -> EditingAssistOutcome {
        support.outcome(for: .insertBacktab, in: text, selection: selection, configuration: configuration)
    }

    private struct CollapsedTabCase {
        let text: String
        let caret: Int
        let padding: String
    }

    @Test("collapsed Tab at width 4 fills to the next stop")
    func collapsedTabWidthFour() {
        let cases = [
            CollapsedTabCase(text: "", caret: 0, padding: "    "), // column 0 → 4
            CollapsedTabCase(text: "a", caret: 1, padding: "   "), // column 1 → 3
            CollapsedTabCase(text: "ab", caret: 2, padding: "  "), // column 2 → 2
            CollapsedTabCase(text: "abc", caret: 3, padding: " "), // column 3 → 1
            CollapsedTabCase(text: "abcd", caret: 4, padding: "    "), // column 4 → full width
        ]
        for testCase in cases {
            let outcome = pressTab(in: testCase.text, selection: NSRange(location: testCase.caret, length: 0))
            let result = support.applied(outcome, to: testCase.text)
            #expect(result?.text == testCase.text + testCase.padding, "\(testCase.text) at \(testCase.caret)")
            #expect(
                result?.selection == NSRange(location: testCase.caret + testCase.padding.utf16.count, length: 0),
                "\(testCase.text) at \(testCase.caret)"
            )
        }
    }

    @Test("collapsed Tab respects widths 2 and 8")
    func collapsedTabOtherWidths() {
        var widthTwo = EditingAssistConfiguration.markdownDefault
        widthTwo.indentationWidth = 2
        let two = pressTab(in: "a", selection: NSRange(location: 1, length: 0), configuration: widthTwo)
        let twoResult = support.applied(two, to: "a")
        #expect(twoResult?.text == "a ")

        var widthEight = EditingAssistConfiguration.markdownDefault
        widthEight.indentationWidth = 8
        let eight = pressTab(in: "a", selection: NSRange(location: 1, length: 0), configuration: widthEight)
        let eightResult = support.applied(eight, to: "a")
        #expect(eightResult?.text == "a       ")
    }

    @Test("collapsed Tab with conversion disabled passes through")
    func collapsedTabConversionDisabledPassesThrough() {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.convertsTabsToSpaces = false
        #expect(pressTab(in: "x", selection: NSRange(location: 1, length: 0), configuration: configuration) ==
            .passthrough)
    }

    @Test("selected lines indent with exactly width spaces")
    func selectedLinesIndent() {
        let text = "ab\ncd"
        let outcome = pressTab(in: text, selection: NSRange(location: 0, length: 5))
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "    ab\n    cd")
        #expect(result?.selection == NSRange(location: 0, length: 13))
    }

    @Test("selection ending at newline does not create a synthetic padded line")
    func selectionEndingAtNewlineNoSyntheticPad() {
        let text = "ab\ncd"
        let outcome = pressTab(in: text, selection: NSRange(location: 0, length: 3))
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "    ab\ncd")
        #expect(result?.selection == NSRange(location: 0, length: 7))
    }

    @Test("selected Shift-Tab removes one tab or configured spaces")
    func selectedShiftTabRemovesIndent() {
        let spaces = "    ab\n    cd"
        let spaceOutcome = pressBacktab(in: spaces, selection: NSRange(location: 0, length: 13))
        let spaceResult = support.applied(spaceOutcome, to: spaces)
        #expect(spaceResult?.text == "ab\ncd")
        #expect(spaceResult?.selection == NSRange(location: 0, length: 5))

        let tabs = "\tab\n  cd"
        let tabOutcome = pressBacktab(in: tabs, selection: NSRange(location: 0, length: 8))
        let tabResult = support.applied(tabOutcome, to: tabs)
        #expect(tabResult?.text == "ab\ncd")
        #expect(tabResult?.selection == NSRange(location: 0, length: 5))
    }

    @Test("selected Shift-Tab leaves unindented lines untouched")
    func selectedShiftTabMixedLines() {
        let text = "    ab\ncd"
        let outcome = pressBacktab(in: text, selection: NSRange(location: 0, length: 8))
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "ab\ncd")
        #expect(result?.selection == NSRange(location: 0, length: 4))
    }

    @Test("collapsed Shift-Tab moves back to the previous indentation stop")
    func collapsedShiftTabToPreviousStop() {
        // Four spaces at width 4 → column 0.
        let four = pressBacktab(in: "    ", selection: NSRange(location: 4, length: 0))
        let fourResult = support.applied(four, to: "    ")
        #expect(fourResult?.text == "")
        #expect(fourResult?.selection == NSRange(location: 0, length: 0))

        // Five spaces: back one stop (one space, since 5 % 4 == 1).
        let five = pressBacktab(in: "     ", selection: NSRange(location: 5, length: 0))
        let fiveResult = support.applied(five, to: "     ")
        #expect(fiveResult?.text == "    ")
        #expect(fiveResult?.selection == NSRange(location: 4, length: 0))

        // A tab is removed as one unit.
        let tab = pressBacktab(in: "\t", selection: NSRange(location: 1, length: 0))
        let tabResult = support.applied(tab, to: "\t")
        #expect(tabResult?.text == "")
        #expect(tabResult?.selection == NSRange(location: 0, length: 0))
    }

    @Test("collapsed Shift-Tab passes through when nothing can be unindented")
    func collapsedShiftTabNothingRemovable() {
        #expect(pressBacktab(in: "x", selection: NSRange(location: 0, length: 0)) == .passthrough)
        #expect(pressBacktab(in: "x", selection: NSRange(location: 1, length: 0)) == .passthrough)
        #expect(pressBacktab(in: "  - x", selection: NSRange(location: 4, length: 0)) == .passthrough)
    }

    @Test("UTF-16 selection around emoji remaps correctly")
    func utf16SelectionRemapsAroundEmoji() {
        let text = "\u{1F680}ab\ncd"
        let outcome = pressTab(in: text, selection: NSRange(location: 0, length: 7))
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "    \u{1F680}ab\n    cd")
        #expect(result?.selection == NSRange(location: 0, length: 15))
    }
}

@Suite("Editing assists — smart Home")
struct EditingAssistSmartHomeTests {
    private let support = EditingAssistTestSupport.self

    private func pressHome(in text: String, selection: NSRange) -> EditingAssistOutcome {
        support.outcome(for: .smartHome, in: text, selection: selection)
    }

    @Test("indented line first trigger moves to first non-whitespace")
    func firstTriggerMovesToFirstNonWhitespace() {
        let outcome = pressHome(in: "    foo", selection: NSRange(location: 7, length: 0))
        #expect(outcome == .selection(NSRange(location: 4, length: 0)))
    }

    @Test("second trigger moves to physical line start")
    func secondTriggerMovesToLineStart() {
        let outcome = pressHome(in: "    foo", selection: NSRange(location: 4, length: 0))
        #expect(outcome == .selection(NSRange(location: 0, length: 0)))
    }

    @Test("unindented line moves to start")
    func unindentedLineMovesToStart() {
        let outcome = pressHome(in: "foo", selection: NSRange(location: 3, length: 0))
        #expect(outcome == .selection(NSRange(location: 0, length: 0)))
    }

    @Test("all-whitespace line moves to start")
    func allWhitespaceLineMovesToStart() {
        let outcome = pressHome(in: "    ", selection: NSRange(location: 4, length: 0))
        #expect(outcome == .selection(NSRange(location: 0, length: 0)))
    }

    @Test("non-empty selection collapses to the target")
    func selectionCollapsesToTarget() {
        let outcome = pressHome(in: "    foo", selection: NSRange(location: 4, length: 3))
        #expect(outcome == .selection(NSRange(location: 0, length: 0)))
    }

    @Test("previous lines containing emoji do not corrupt the current UTF-16 position")
    func emojiOnPreviousLineDoesNotCorruptPosition() {
        let outcome = pressHome(in: "\u{1F680}\n    foo", selection: NSRange(location: 10, length: 0))
        #expect(outcome == .selection(NSRange(location: 7, length: 0)))
    }
}
