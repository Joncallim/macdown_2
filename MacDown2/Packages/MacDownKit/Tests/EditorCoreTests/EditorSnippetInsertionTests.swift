import AppKit
@testable import EditorCore
import FileCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem.insertSnippet (EPIC-22 Slice 9e)")
struct EditorSnippetInsertionTests {
    private let support = EditingAssistIntegrationSupport.self

    private func mounted(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        system.textView.delegate = support.makeCoordinator(system: system)
        return (system, window)
    }

    @Test func insertsAtASingleCaretAndPlacesTheCaretAtDollarZero() {
        let (system, window) = mounted("ab")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 1, length: 0)

        #expect(system.insertSnippet(SnippetTemplate(parsing: "[$0]"), clipboard: nil))

        #expect(system.textView.string == "a[]b")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 0)])
    }

    @Test func aSelectionIsWrappedViaTheSelectionToken() {
        let (system, window) = mounted("say hi now")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 2)

        system.insertSnippet(SnippetTemplate(parsing: "**${selection}**$0"), clipboard: nil)

        #expect(system.textView.string == "say **hi** now")
        #expect(system.selectionSet.primaryRange == NSRange(location: 10, length: 0))
    }

    @Test func multipleCaretsEachExpandOnceAndKeepTheirOwnCaret() {
        let (system, window) = mounted("one\ntwo\nthree")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [
                NSRange(location: 3, length: 0),
                NSRange(location: 7, length: 0),
                NSRange(location: 13, length: 0),
            ],
            primaryIndex: 1
        )

        #expect(system.insertSnippet(SnippetTemplate(parsing: "(<$0>)"), clipboard: nil))

        #expect(system.textView.string == "one(<>)\ntwo(<>)\nthree(<>)")
        #expect(system.selectionSet.ranges == [
            NSRange(location: 5, length: 0),
            NSRange(location: 13, length: 0),
            NSRange(location: 23, length: 0),
        ])
        #expect(system.selectionSet.primaryIndex == 1)
    }

    @Test func eachCaretUsesItsOwnSelectionAndItsOwnIndentation() {
        let (system, window) = mounted("  ab\n\t\tcd")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 2, length: 2), NSRange(location: 7, length: 2)],
            primaryIndex: 0
        )

        system.insertSnippet(SnippetTemplate(parsing: "<${selection}\n>$0"), clipboard: nil)

        #expect(system.textView.string == "  <ab\n  >\n\t\t<cd\n\t\t>")
        #expect(system.selectionSet.ranges.count == 2)
    }

    @Test func continuationLinesFollowTheDocumentsCRLFTerminator() {
        let (system, window) = mounted("a\r\nb")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 1, length: 0)

        system.insertSnippet(SnippetTemplate(parsing: "x\ny"), clipboard: nil)

        #expect(system.textView.string == "ax\r\ny\r\nb")
    }

    @Test func aDocumentWithoutTerminatorsUsesTheSuppliedDefault() {
        let (system, window) = mounted("")
        defer { window.orderOut(nil) }

        system.insertSnippet(SnippetTemplate(parsing: "x\ny"), clipboard: nil, defaultLineEnding: .crlf)

        #expect(system.textView.string == "x\r\ny")
    }

    @Test func aMissingClipboardLeavesNoTokenBehind() {
        let (system, window) = mounted("")
        defer { window.orderOut(nil) }

        system.insertSnippet(SnippetTemplate(parsing: "<${clipboard}>"), clipboard: nil)

        #expect(system.textView.string == "<>")
    }

    @Test func theWholeInsertionIsOneUndoStep() {
        let (system, window) = mounted("a b")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        system.insertSnippet(SnippetTemplate(parsing: "[$0]"), clipboard: nil)
        #expect(system.textView.string == "a[] b[]")
        system.textView.undoManager?.undo()

        #expect(system.textView.string == "a b")
    }

    @Test func anActiveIMECompositionFailsOpenAndChangesNothing() {
        let (system, window) = mounted("hello")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 5, length: 0)
        system.textView.setMarkedText(
            "\u{3042}",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let before = system.textView.string

        #expect(!system.insertSnippet(SnippetTemplate(parsing: "SNIP"), clipboard: nil))
        #expect(system.textView.string == before)
    }

    @Test func aReadOnlyViewIsNeverModified() {
        let (system, window) = mounted("abc")
        defer { window.orderOut(nil) }
        system.textView.isEditable = false

        #expect(!system.insertSnippet(SnippetTemplate(parsing: "SNIP"), clipboard: nil))
        #expect(system.textView.string == "abc")
    }

    @Test func aSurrogatePairSelectionIsReplacedWhole() {
        let (system, window) = mounted("a\u{1F600}b")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 1, length: 2)

        system.insertSnippet(SnippetTemplate(parsing: "<${selection}>"), clipboard: nil)

        #expect(system.textView.string == "a<\u{1F600}>b")
    }

    @Test func clipboardLineBreaksFollowTheDocumentsLineEnding() {
        let (lineFeedSystem, lfWindow) = mounted("x\ny\n")
        defer { lfWindow.orderOut(nil) }
        lineFeedSystem.selectedRange = NSRange(location: 0, length: 0)
        lineFeedSystem.insertSnippet(SnippetTemplate(parsing: "${clipboard}$0"), clipboard: "p\r\nq")
        #expect(lineFeedSystem.textView.string == "p\nqx\ny\n")

        let (crlfSystem, crlfWindow) = mounted("x\r\ny\r\n")
        defer { crlfWindow.orderOut(nil) }
        crlfSystem.selectedRange = NSRange(location: 0, length: 0)
        crlfSystem.insertSnippet(SnippetTemplate(parsing: "${clipboard}$0"), clipboard: "p\nq\rr")
        #expect(crlfSystem.textView.string == "p\r\nq\r\nrx\r\ny\r\n")
    }

    @Test func aSelectionIsInsertedVerbatim() {
        let (system, window) = mounted("a\r\nb")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 4)

        system.insertSnippet(SnippetTemplate(parsing: "[${selection}]"), clipboard: nil)

        #expect(system.textView.string == "[a\r\nb]")
    }
}
