import AppKit
@testable import EditorCore
import FileCore
import Foundation
import Testing

@Suite("EditorTextTransforms line endings (Slice 8c)")
struct EditorTextTransformsLineEndingsTests {
    private func convert(
        _ text: String,
        to target: LineEnding,
        selection: NSRange = NSRange(location: 0, length: 0)
    ) -> (text: String, selection: NSRange)? {
        let source = text as NSString
        let transaction = EditorTextTransforms.convertLineEndingsTransaction(
            text: source,
            selection: EditorSelectionSet(single: selection),
            target: target
        )
        return LineTransformTestSupport.applied(transaction, to: text)
    }

    @Test(arguments: [
        ("a\nb\nc", LineEnding.crlf, "a\r\nb\r\nc"),
        ("a\nb\nc", .carriageReturn, "a\rb\rc"),
        ("a\r\nb\r\nc", .lineFeed, "a\nb\nc"),
        ("a\r\nb\r\nc", .carriageReturn, "a\rb\rc"),
        ("a\rb\rc", .lineFeed, "a\nb\nc"),
        ("a\rb\rc", .crlf, "a\r\nb\r\nc"),
        ("a\nb\r\nc\rd\n", .lineFeed, "a\nb\nc\nd\n"),
        ("a\nb\r\nc\rd\n", .crlf, "a\r\nb\r\nc\r\nd\r\n"),
        ("a\nb\r\nc\rd\n", .carriageReturn, "a\rb\rc\rd\r"),
        ("\n\n", .crlf, "\r\n\r\n"),
    ])
    func convertsEveryTerminator(text: String, target: LineEnding, expected: String) {
        #expect(convert(text, to: target)?.text == expected)
    }

    @Test func alreadyUniformTargetIsANoOp() {
        #expect(convert("a\nb\n", to: .lineFeed) == nil)
        #expect(convert("a\r\nb", to: .crlf) == nil)
        #expect(convert("a\rb", to: .carriageReturn) == nil)
        #expect(convert("no terminators", to: .crlf) == nil)
        #expect(convert("", to: .lineFeed) == nil)
    }

    @Test func mixedTextWithTargetTerminatorsInsideTheSpanIsFullyConverted() {
        let result = convert("x\r\na\nb\r\ny", to: .crlf)
        #expect(result?.text == "x\r\na\r\nb\r\ny")
    }

    @Test func contentOutsideTheChangedSpanIsUntouched() {
        let source = "keep\r\nkeep\r\nfix\nkeep\r\nkeep" as NSString
        let transaction = EditorTextTransforms.convertLineEndingsTransaction(
            text: source, selection: EditorSelectionSet(single: NSRange(location: 0, length: 0)), target: .crlf
        )
        #expect(transaction?.replacements.count == 1)
        #expect(transaction?.replacements.first?.range == NSRange(location: 15, length: 1))
    }

    @Test func nonBMPAndCombiningContentSurvives() {
        let text = "😀\ne\u{301}\n👨‍👩‍👧"
        #expect(convert(text, to: .crlf)?.text == "😀\r\ne\u{301}\r\n👨‍👩‍👧")
    }

    @Test func unicodeSeparatorsAreContentNotTerminators() {
        #expect(convert("a\u{2028}b\nc", to: .crlf)?.text == "a\u{2028}b\r\nc")
    }

    @Test func caretIsRemappedThroughLengthChanges() {
        // "a\nb\nc": caret after 'b' (offset 3) moves to 4 after LF→CRLF.
        #expect(convert("a\nb\nc", to: .crlf, selection: NSRange(location: 3, length: 0))?.selection
            == NSRange(location: 4, length: 0))
        // CRLF→LF: caret after 'b' (offset 4) moves to 3.
        #expect(convert("a\r\nb\r\nc", to: .lineFeed, selection: NSRange(location: 4, length: 0))?.selection
            == NSRange(location: 3, length: 0))
    }

    @Test func caretInsideACRLFClampsWithinTheNewTerminator() {
        // Between the CR and LF (offset 2) → after the single LF's start + 1 clamp.
        #expect(convert("a\r\nb", to: .lineFeed, selection: NSRange(location: 2, length: 0))?.selection
            == NSRange(location: 2, length: 0))
        #expect(convert("a\r\nb", to: .carriageReturn, selection: NSRange(location: 2, length: 0))?.selection
            == NSRange(location: 2, length: 0))
    }

    @Test func selectionSpanningTerminatorsKeepsItsContent() {
        let result = convert("ab\ncd\nef", to: .crlf, selection: NSRange(location: 1, length: 6))
        #expect(result?.text == "ab\r\ncd\r\nef")
        #expect(result?.selection == NSRange(location: 1, length: 8))
    }

    @Test func largeDocumentIsOneReplacement() {
        let text = String(repeating: "line\n", count: 20000)
        let transaction = EditorTextTransforms.convertLineEndingsTransaction(
            text: text as NSString,
            selection: EditorSelectionSet(single: NSRange(location: 0, length: 0)),
            target: .crlf
        )
        #expect(transaction?.replacements.count == 1)
        #expect(transaction?.undoActionName == "Convert Line Endings")
    }
}

@MainActor
@Suite("EditorTextSystem convertLineEndings (Slice 8c)")
struct EditorTextSystemLineEndingsTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func convertsTheWholeDocumentAsOneUndoStep() {
        let system = support.makeSystem(text: "a\nb\r\nc\rd")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        #expect(system.convertLineEndings(to: .crlf))
        #expect(system.textView.string == "a\r\nb\r\nc\r\nd")
        system.textView.undoManager?.undo()
        #expect(system.textView.string == "a\nb\r\nc\rd")
        #expect(system.lineIndex.lineCount == 4)
    }

    @Test func returnsFalseWhenNothingChanges() {
        let system = support.makeSystem(text: "a\nb")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        #expect(!system.convertLineEndings(to: .lineFeed))
        #expect(system.textView.undoManager?.canUndo != true)
    }
}
