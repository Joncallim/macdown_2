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

    @Test func caretInsideACRLFLandsAfterTheReplacementTerminator() {
        // Offset 2 is between the CR and LF; the single-unit replacement ends at 2.
        #expect(convert("a\r\nb", to: .lineFeed, selection: NSRange(location: 2, length: 0))?.selection
            == NSRange(location: 2, length: 0))
        #expect(convert("a\r\nb", to: .carriageReturn, selection: NSRange(location: 2, length: 0))?.selection
            == NSRange(location: 2, length: 0))
        // A later terminator still shifts the caret by the earlier one's delta.
        #expect(convert("a\r\nb\r\nc", to: .lineFeed, selection: NSRange(location: 5, length: 0))?.selection
            == NSRange(location: 4, length: 0))
    }

    @Test func rangeEndingInsideACRLFKeepsTheWholeTerminator() {
        let result = convert("ab\r\ncd", to: .lineFeed, selection: NSRange(location: 0, length: 3))
        #expect(result?.text == "ab\ncd")
        #expect(result?.selection == NSRange(location: 0, length: 3))
    }

    @Test func rangeStartingInsideACRLFExcludesTheWholeTerminator() {
        let result = convert("ab\r\ncd", to: .lineFeed, selection: NSRange(location: 3, length: 2))
        #expect(result?.selection == NSRange(location: 3, length: 1))
    }

    @Test func caretAfterTheChangedSpanShiftsByTheTotalDelta() {
        // Two changed terminators, caret in the unchanged tail.
        #expect(convert("a\nb\nc\r\nd", to: .crlf, selection: NSRange(location: 8, length: 0))?.selection
            == NSRange(location: 10, length: 0))
    }

    @Test func caretBetweenUnchangedTerminatorsInsideTheSpanShiftsByThoseBefore() {
        // "a\nb\r\nc\nd": the middle CRLF is already the target; the caret after
        // 'c' (offset 6) has one earlier LF→CRLF change (+1) and one later one.
        #expect(convert("a\nb\r\nc\nd", to: .crlf, selection: NSRange(location: 6, length: 0))?.selection
            == NSRange(location: 7, length: 0))
    }

    @Test func trailingLoneCarriageReturnConverts() {
        #expect(convert("a\r", to: .crlf)?.text == "a\r\n")
        #expect(convert("a\r", to: .lineFeed)?.text == "a\n")
        #expect(convert("a\r\n\r", to: .lineFeed)?.text == "a\n\n")
    }

    @Test func everySelectionIsRemappedAndThePrimaryIndexIsPreserved() {
        let source = "ab\ncd\nef" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0), NSRange(location: 7, length: 1)],
            primaryIndex: 1
        )
        let transaction = EditorTextTransforms.convertLineEndingsTransaction(
            text: source, selection: selection, target: .crlf
        )
        #expect(transaction?.resultingSelection?.ranges == [
            NSRange(location: 1, length: 0),
            NSRange(location: 5, length: 0),
            NSRange(location: 9, length: 1),
        ])
        #expect(transaction?.resultingSelection?.primaryIndex == 1)
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
        let replacement = transaction?.replacements.first
        #expect(replacement?.range == NSRange(location: 4, length: 5 * 20000 - 4))
        #expect(replacement?.replacementText.utf16.count == 2 + 19999 * 6)
        #expect(replacement?.replacementText.hasSuffix("line\r\n") == true)
        #expect(replacement?.replacementText.contains("\n\n") == false)
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
        system.textView.undoManager?.redo()
        #expect(system.textView.string == "a\r\nb\r\nc\r\nd")
    }

    @Test func undoActionIsNamedConvertLineEndings() {
        let system = support.makeSystem(text: "a\nb")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        #expect(system.convertLineEndings(to: .carriageReturn))
        #expect(system.textView.undoManager?.undoActionName == "Convert Line Endings")
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
