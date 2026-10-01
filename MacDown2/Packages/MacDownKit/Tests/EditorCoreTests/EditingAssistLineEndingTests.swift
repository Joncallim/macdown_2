import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Return must never introduce a second line-ending convention into a document
/// (invariant #5), including on the last line, which has no terminator of its own.
@MainActor
@Suite("Editing assists — Return follows the document's line ending")
struct EditingAssistLineEndingTests {
    private let support = EditingAssistTestSupport.self

    private func pressReturn(in text: String, at location: Int) -> String? {
        let outcome = support.outcome(for: .insertNewline, in: text, selection: NSRange(location: location, length: 0))
        return support.applied(outcome, to: text)?.text
    }

    @Test func lastLineOfACRLFDocumentWithoutATrailingNewlineGetsCRLF() {
        let text = "- one\r\n- two"
        #expect(pressReturn(in: text, at: text.utf16.count) == "- one\r\n- two\r\n- ")
    }

    @Test func aLinefeedDocumentStaysLinefeed() {
        let text = "- one\n- two"
        #expect(pressReturn(in: text, at: text.utf16.count) == "- one\n- two\n- ")
    }

    @Test func theSeparatorHelperHandlesBareCRAndTerminatorlessText() {
        let bareCR = "para one\rpara two" as NSString
        #expect(MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: bareCR.length, in: bareCR) == "\r")
        #expect(MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: 2, in: bareCR) == "\r")
        let plain = "plain" as NSString
        #expect(MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: 5, in: plain) == "\n")
    }

    @Test func indentationContinuationOnTheLastLineOfACRLFDocumentUsesCRLF() {
        let text = "a\r\n    code"
        #expect(pressReturn(in: text, at: text.utf16.count) == "a\r\n    code\r\n    ")
    }

    // MARK: - Through the real coordinator (the AppKit fall-through path)

    private struct ReturnResult {
        let handled: Bool
        let text: String
        let selection: NSRange
    }

    private func returnKey(in text: String, at location: Int, assistsEnabled: Bool) -> ReturnResult {
        let system = assistsEnabled
            ? EditingAssistIntegrationSupport.makeMarkdownSystem(text: text)
            : EditingAssistIntegrationSupport.makeSystem(text: text)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: location, length: 0)
        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        return ReturnResult(handled: handled, text: system.text, selection: system.selectedRange)
    }

    @Test func plainReturnInACRLFDocumentInsertsCRLFWithAssistsOn() {
        let result = returnKey(in: "alpha\r\nbeta", at: 4, assistsEnabled: true)
        #expect(result.handled)
        #expect(result.text == "alph\r\na\r\nbeta")
        #expect(result.selection == NSRange(location: 6, length: 0))
    }

    @Test func plainReturnInACRLFDocumentInsertsCRLFWithAssistsOff() {
        let result = returnKey(in: "alpha\r\nbeta", at: 11, assistsEnabled: false)
        #expect(result.handled)
        #expect(result.text == "alpha\r\nbeta\r\n")
    }

    @Test func plainReturnInALinefeedDocumentIsLeftToAppKit() {
        let result = returnKey(in: "alpha\nbeta", at: 4, assistsEnabled: true)
        #expect(!result.handled)
    }

    @Test func listContinuationStillWinsOverTheLineEndingFallback() {
        let result = returnKey(in: "- one\r\n- two", at: 12, assistsEnabled: true)
        #expect(result.handled)
        #expect(result.text == "- one\r\n- two\r\n- ")
    }

    @Test func returnDuringIMECompositionIsNotIntercepted() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "a\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.textView.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 4, length: 0)
        )

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(!handled)
    }

    @Test func returnReplacesASelectionWithTheDocumentsSeparator() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "ab\r\ncd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 1)

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(handled)
        #expect(system.text == "\r\nb\r\ncd")
        #expect(system.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test func everyRangeOfAMultiSelectionIsReplacedWithTheDocumentsSeparator() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "ab\r\ncd\r\nef")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 1), NSRange(location: 4, length: 1)],
            primaryIndex: 0
        )

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(handled)
        #expect(system.text == "\r\nb\r\n\r\nd\r\nef")
    }

    @Test(arguments: [
        #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
        #selector(NSResponder.insertLineBreak(_:)),
        #selector(NSResponder.insertParagraphSeparator(_:)),
    ])
    func theOtherNewlineSelectorsAlsoFollowTheDocument(_ selector: Selector) {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "ab\r\ncd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 1, length: 0)

        #expect(coordinator.textView(system.textView, doCommandBy: selector))
        #expect(system.text == "a\r\nb\r\ncd")
    }

    @Test func aReadOnlyEditorIsNotIntercepted() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "ab\r\ncd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.textView.isEditable = false
        system.selectedRange = NSRange(location: 1, length: 0)

        #expect(!coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(system.text == "ab\r\ncd")
    }

    @Test func imeCompositionIsNotInterceptedWithAssistsOn() {
        let system = EditingAssistIntegrationSupport.makeMarkdownSystem(text: "a\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.textView.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 4, length: 0)
        )

        #expect(!coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }
}
