@testable import EditorCore
import Foundation
import Testing

/// `remappedSelection` returns a position relative to the edited range, but `resultingSelection` is absolute, so any
/// line-based assist away from the first line put the selection in the wrong place (Tab on a selection selected
/// "aaa\n   " and the next keystroke replaced it; Heading from line 3 put the caret in line 1).
struct EditingAssistSelectionPositionTests {
    private let support = EditingAssistTestSupport.self

    @Test("Tab on a selection in the second line keeps the selection on that line")
    func tabOnASelectionAwayFromTheFirstLine() {
        let text = "aaa\nbbb\nccc"
        let outcome = support.outcome(for: .insertTab, in: text, selection: NSRange(location: 4, length: 3))

        let result = support.applied(outcome, to: text)

        #expect(result?.text == "aaa\n    bbb\nccc")
        let selected = result.map { ($0.text as NSString).substring(with: $0.selection) }
        #expect(selected == "    bbb")
    }

    @Test("Shift-Tab on a selection in the third line keeps the selection on that line")
    func backtabOnASelectionAwayFromTheFirstLine() {
        let text = "aaa\nbbb\n    ccc"
        let outcome = support.outcome(for: .insertBacktab, in: text, selection: NSRange(location: 8, length: 7))

        let result = support.applied(outcome, to: text)

        #expect(result?.text == "aaa\nbbb\nccc")
        let selected = result.map { ($0.text as NSString).substring(with: $0.selection) }
        #expect(selected == "ccc")
    }

    @Test("Heading from a caret in the third line leaves the caret in that line")
    func headingAwayFromTheFirstLine() {
        let text = "aaa\nbbb\nccc"
        let outcome = support.outcome(
            for: .markdownCommand(.heading(level: 2)),
            in: text,
            selection: NSRange(location: 9, length: 0)
        )

        let result = support.applied(outcome, to: text)

        #expect(result?.text == "aaa\nbbb\n## ccc")
        #expect(result?.selection == NSRange(location: 12, length: 0))
    }
}
