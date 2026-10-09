import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Marked-text (IME / dead-key) edits and edits that leave the primary range alone post no `didChange`, so derived
/// state went stale: a cancelled composition over a selection left the line index wrong (a later line command
/// crashed or deleted the wrong text), a cached secondary caret outlived the text it pointed into (the next arrow
/// key crashed), and Undo during a composition corrupted or crashed.
@MainActor
struct EditorCompositionStateTests {
    private let support = EditingAssistIntegrationSupport.self
    private let unset = NSRange(location: NSNotFound, length: 0)

    private func mounted(_ text: String) -> (system: EditorTextSystem, window: NSWindow) {
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        _ = support.makeCoordinator(system: system)
        return (system, window)
    }

    @Test func aCancelledCompositionOverASelectionLeavesTheLineIndexCorrect() {
        let (system, window) = mounted("a\nb\nc\nd")
        defer { window.orderOut(nil) }
        system.textView.setSelectedRange(NSRange(location: 0, length: 3))

        system.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: unset)
        system.textView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: unset)
        system.textView.unmarkText()

        #expect(system.lineIndex == EditorLineIndex(text: system.text as NSString))
        system.textView.setSelectedRange(NSRange(location: 2, length: 0))
        system.moveLinesDown() // used to raise NSRangeException on the stale index
        #expect(system.lineIndex == EditorLineIndex(text: system.text as NSString))
    }

    @Test func aStaleSecondaryCaretIsDroppedWhenTheTextShrinksUnderIt() {
        let (system, window) = mounted("abc def")
        defer { window.orderOut(nil) }
        system.textView.setSelectedRange(NSRange(location: 3, length: 0))
        system.toggleSecondaryCaret(at: 7)

        system.textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        let length = (system.text as NSString).length
        #expect(system.selectionSet.ranges.allSatisfy { NSMaxRange($0) <= length })
        system.textView.doCommand(by: #selector(NSResponder.moveLeft(_:))) // used to raise NSInvalidArgumentException
    }

    @Test func undoDuringACompositionEndsItAndUndoesTheEarlierEdit() {
        let (system, window) = mounted("hello world")
        defer { window.orderOut(nil) }
        window.makeFirstResponder(system.textView)
        system.textView.setSelectedRange(NSRange(location: 3, length: 0))
        system.textView.insertText("X", replacementRange: NSRange(location: 3, length: 0))
        #expect(system.text == "helXlo world")
        system.textView.setSelectedRange(NSRange(location: 5, length: 0))

        system.textView.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0), replacementRange: unset)
        (system.textView as? EditorTextView)?.undo(nil)

        #expect(!system.textView.hasMarkedText())
        #expect(system.text == "hello world")
        #expect(system.lineIndex == EditorLineIndex(text: system.text as NSString))
    }
}
