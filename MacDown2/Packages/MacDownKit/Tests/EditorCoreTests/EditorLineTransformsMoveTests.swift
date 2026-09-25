@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-i — Move Line Up/Down's own pure-logic tests,
/// split out of `EditorLineTransformsTests.swift` to stay under swiftlint's
/// type-body-length limit once Duplicate/Delete/Join were also added there.
@Suite("EditorLineTransforms — Move Line Up/Down (Slice 4c-i)")
struct EditorLineTransformsMoveTests {
    @Test("moving a line up swaps it with the line above")
    func moveLineUp() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location + 1
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\nAAA\nCCC")
        #expect(applied?.selection == NSRange(location: 1, length: 0)) // same column, now on line 1
    }

    @Test("moving a line down swaps it with the line below")
    func moveLineDown() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location + 1
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.moveLinesDownTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA\nCCC\nBBB")
        #expect(applied?.selection == NSRange(location: 9, length: 0))
    }

    @Test("moving the document's first line up is a no-op")
    func moveFirstLineUpIsNoOp() {
        let text = "AAA\nBBB" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("moving the document's last line down is a no-op")
    func moveLastLineDownIsNoOp() {
        let text = "AAA\nBBB" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: text.length, length: 0))

        let transaction = EditorLineTransforms.moveLinesDownTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("moving a multi-line block up moves it past exactly one line, preserving internal order")
    func moveMultiLineBlockUp() {
        let text = "AAA\nBBB\nCCC\nDDD" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 4, length: 7)) // "BBB\nCCC"

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\nCCC\nAAA\nDDD")
    }

    @Test("moving the last line (no trailing newline) up correctly transplants the terminator")
    func moveLastLineUpTransplantsTerminator() {
        let text = "AAA\nBBB" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: text.length, length: 0)) // on "BBB"

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\nAAA") // "AAA" is now last, correctly has no trailing newline
    }

    // MARK: - Non-LF line endings (a P1 an independent hostile review found)

    @Test("moving a line up in a CRLF document preserves every CRLF terminator verbatim")
    func moveLineUpPreservesCRLF() {
        // The original implementation rejoined bare line content with a
        // literal "\n", silently downgrading this document's own CRLF
        // terminators to LF within the swapped span -- confirmed as a real,
        // silent-corruption bug for any Windows-authored or
        // core.autocrlf-checked-out file.
        let text = "AAA\r\nBBB\r\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\r\nAAA\r\nCCC")
    }

    @Test("moving a line down in a CRLF document preserves every CRLF terminator verbatim")
    func moveLineDownPreservesCRLF() {
        let text = "AAA\r\nBBB\r\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "AAA").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.moveLinesDownTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\r\nAAA\r\nCCC")
    }

    @Test("moving a multi-line block preserves its own internal CRLF terminators")
    func moveMultiLineBlockPreservesInternalCRLF() {
        let text = "AAA\r\nBBB\r\nCCC\r\nDDD" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 5, length: 9)) // "BBB\r\nCCC"

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\r\nCCC\r\nAAA\r\nDDD")
    }

    @Test("moving a line up in a bare-CR (classic Mac OS 9) document preserves every CR terminator")
    func moveLineUpPreservesBareCR() {
        let text = "AAA\rBBB\rCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "BBB\rAAA\rCCC")
    }

    @Test("if ANY active selection is already at the boundary, the whole Move Up command no-ops")
    func moveUpAllOrNothingAcrossMultipleSelections() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        // One caret on line 1 (can't move up), one on line 3 (could move up alone).
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)],
            primaryIndex: 0
        )

        let transaction = EditorLineTransforms.moveLinesUpTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }
}
