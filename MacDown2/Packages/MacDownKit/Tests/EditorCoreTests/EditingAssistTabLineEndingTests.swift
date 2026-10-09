@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: Tab on whole selected lines of a CRLF document indented the
/// (synthetic) line AFTER the selection, and with "Insert spaces for Tab" off a Tab
/// on a selection replaced the selection with one tab character.
@Suite("Editing assists — Tab with CRLF and tabs mode")
struct EditingAssistTabLineEndingTests {
    private let support = EditingAssistTestSupport.self

    private func tab(_ text: String, _ selection: NSRange, tabs: Bool = false) -> (text: String, selection: NSRange)? {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.convertsTabsToSpaces = !tabs
        return support.applied(
            support.outcome(for: .insertTab, in: text, selection: selection, configuration: configuration),
            to: text
        )
    }

    @Test func tabOverWholeCRLFLinesDoesNotIndentTheLineAfterTheSelection() {
        // "a\r\nb\r\n" selected in full, followed by "c".
        let result = tab("a\r\nb\r\nc", NSRange(location: 0, length: 6))
        #expect(result?.text == "    a\r\n    b\r\nc")
    }

    @Test func theLFTwinStillBehaves() {
        #expect(tab("a\nb\nc", NSRange(location: 0, length: 4))?.text == "    a\n    b\nc")
    }

    @Test func tabOnASelectionInTabsModeIndentsTheLinesInsteadOfReplacingThem() {
        let text = "line one\nline two\nline three"
        let result = tab(text, NSRange(location: 0, length: 17), tabs: true)
        #expect(result?.text == "\tline one\n\tline two\nline three")
    }

    @Test func aCollapsedTabInTabsModeStillPassesThrough() {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.convertsTabsToSpaces = false
        #expect(support.outcome(
            for: .insertTab, in: "x", selection: NSRange(location: 1, length: 0), configuration: configuration
        ) == .passthrough)
    }
}
