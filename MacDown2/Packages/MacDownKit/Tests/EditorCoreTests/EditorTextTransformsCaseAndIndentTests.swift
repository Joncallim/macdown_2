@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-ii — pure-logic tests for Convert Case and
/// Increase/Decrease Indent, split out of `EditorTextTransformsTests.swift`
/// to stay under swiftlint's type-body-length limit once Sort/Dedupe/Trim
/// were also added there.
@Suite("EditorTextTransforms — Case and Indent (Slice 4c-ii)")
struct EditorTextTransformsCaseAndIndentTests {
    // MARK: - Convert Case

    @Test("uppercase converts the selected text")
    func uppercaseBasic() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "HELLO WORLD")
    }

    @Test("lowercase converts the selected text")
    func lowercaseBasic() {
        let text = "HELLO WORLD" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .lowercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "hello world")
    }

    @Test("capitalized title-cases each word")
    func capitalizedBasic() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .capitalized
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "Hello World")
    }

    @Test("case conversion declines entirely when any active selection is empty")
    func caseConversionDeclinesOnAnyEmptySelection() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 6, length: 0)], // "hello" + a bare caret
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        #expect(transaction == nil)
    }

    @Test("case conversion applies independently to multiple non-empty selections in one transaction")
    func caseConversionMultipleSelections() {
        let text = "cat and dog" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)], // "cat", "dog"
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        #expect(transaction?.replacements.count == 2)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "CAT and DOG")
    }

    @Test("case conversion correctly handles a length-changing uppercase (German ß -> SS)")
    func caseConversionHandlesLengthChangingUppercase() throws {
        let text = "straße" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "STRASSE")
        #expect(try applied?.selection == NSRange(location: 0, length: (#require(applied?.text) as NSString).length))
    }

    // MARK: - Increase / Decrease Indent

    @Test("increase indent adds width spaces to every line the selection touches")
    func increaseIndentBasic() {
        let text = "foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: false
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "    foo\n    bar")
    }

    @Test("decrease indent removes up to width leading spaces from every touched line")
    func decreaseIndentBasic() {
        let text = "    foo\n    bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: true
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar")
    }

    @Test("increase indent works for a bare caret, indenting its own current line")
    func increaseIndentBareCaret() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  foo")
    }

    @Test("decrease indent on an already-flush line is a genuine no-op")
    func decreaseIndentNoOpWhenAlreadyFlush() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: true
        )
        #expect(transaction == nil)
    }

    @Test("two carets on the same line merge into one group -- indenting it exactly once, not twice")
    func indentMergesTwoCaretsOnTheSameLine() {
        let text = "foobar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "  foobar")
    }

    @Test("increase indent on multiple disjoint selections indents each independently")
    func increaseIndentMultipleDisjointSelections() {
        let text = "foo\nbar\nbaz" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)], // line 1, line 3
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        #expect(transaction?.replacements.count == 2)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "  foo\nbar\n  baz")
    }
}
