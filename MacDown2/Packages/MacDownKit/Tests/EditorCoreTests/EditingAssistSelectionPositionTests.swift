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

    /// Review pass 6: an endpoint inside the removed leading whitespace was shifted by the whole (negative) delta and
    /// landed on the previous line's terminator, between a CR and its LF; typing there ate the CR.
    @Test("Shift-Tab with an endpoint inside removed whitespace never lands between a CR and its LF")
    func backtabEndpointInsideRemovedWhitespaceStaysOnItsLine() {
        let text = "abc d\r\n  \r\nzz\r\n"
        let outcome = support.outcome(for: .insertBacktab, in: text, selection: NSRange(location: 2, length: 6))

        let result = support.applied(outcome, to: text)

        #expect(result?.text == "abc d\r\n\r\nzz\r\n")
        let units = Array((result?.text ?? "").utf16)
        let selection = result?.selection ?? NSRange(location: 0, length: 0)
        for boundary in [selection.location, NSMaxRange(selection)] where boundary > 0 && boundary < units.count {
            #expect(!(units[boundary - 1] == 0x0D && units[boundary] == 0x0A), "boundary \(boundary) splits a CRLF")
        }
    }

    @Test("Shift-Tab over CRLF lines never leaves either selection end between a CR and its LF")
    func backtabOverCRLFLinesKeepsBothEndsOffTheTerminator() {
        let text = "  a\r\n    b\r\n  \r\nc\r\n"
        let units = Array(text.utf16)
        for start in 0 ..< units.count {
            for length in 0 ... (units.count - start) {
                let selection = NSRange(location: start, length: length)
                guard !(start > 0 && start < units.count && units[start - 1] == 0x0D && units[start] == 0x0A),
                      !(start + length > 0 && start + length < units.count
                          && units[start + length - 1] == 0x0D && units[start + length] == 0x0A)
                else { continue }
                let outcome = support.outcome(for: .insertBacktab, in: text, selection: selection)
                guard let result = support.applied(outcome, to: text) else { continue }
                let after = Array(result.text.utf16)
                for boundary in [result.selection.location, NSMaxRange(result.selection)]
                    where boundary > 0 && boundary < after.count {
                    #expect(
                        !(after[boundary - 1] == 0x0D && after[boundary] == 0x0A),
                        "selection \(selection) -> boundary \(boundary) in \(result.text.debugDescription)"
                    )
                }
            }
        }
    }
}
