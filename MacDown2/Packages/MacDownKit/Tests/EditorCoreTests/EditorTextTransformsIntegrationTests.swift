import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-ii — `EditorTextSystem`'s own adapter methods
/// (`sortLines()`/`dedupeLines()`/`trimTrailingWhitespace()`/
/// `convertCase(_:)`/`increaseIndent()`/`decreaseIndent()`), mounted against
/// a real `NSTextView`/window -- `EditorTextTransforms` itself already has
/// its own exhaustive pure-logic suites; these tests are specifically about
/// the ADAPTER's own wiring, not the transform logic.
@MainActor
@Suite("EditorTextSystem text transforms (Slice 4c-ii)")
struct EditorTextTransformsIntegrationTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func sortLinesUpdatesTextAndLineIndex() {
        let system = support.makeSystem(text: "banana\napple\ncherry")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 19)

        let handled = system.sortLines()

        #expect(handled)
        #expect(system.textView.string == "apple\nbanana\ncherry")
        #expect(system.lineIndex.lineCount == 3)
    }

    @Test func dedupeLinesRemovesDuplicatesAndRegistersOneUndoStep() {
        let system = support.makeSystem(text: "apple\nbanana\napple")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 18)

        let handled = system.dedupeLines()

        #expect(handled)
        #expect(system.textView.string == "apple\nbanana")
        #expect(system.textView.undoManager?.canUndo == true)
        system.textView.undoManager?.undo()
        #expect(system.textView.string == "apple\nbanana\napple")
    }

    @Test func trimTrailingWhitespaceCleansTheWholeDocumentRegardlessOfSelection() {
        let system = support.makeSystem(text: "foo  \nbar\t")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.trimTrailingWhitespace()

        #expect(handled)
        #expect(system.textView.string == "foo\nbar")
    }

    @Test func convertCaseUppercasesTheSelection() {
        let system = support.makeSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 5)

        let handled = system.convertCase(.uppercase)

        #expect(handled)
        #expect(system.textView.string == "HELLO")
    }

    @Test func convertCaseDeclinesOnABareCaret() {
        let system = support.makeSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 2, length: 0)

        #expect(system.convertCase(.uppercase) == false)
        #expect(system.textView.string == "hello")
    }

    @Test func increaseIndentUsesTheGlobalIndentationWidthWhenNoProfileOverrideExists() {
        let system = support.makeSystem(text: "foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.increaseIndent()

        #expect(handled)
        // `.plainText`'s own default profile has no `defaultIndentWidth`
        // override, so this falls back to the global `indentationWidth`
        // (4, `EditingAssistConfiguration.disabled`'s own default -- the
        // default `EditorConfiguration` this system was constructed with).
        #expect(system.textView.string == "    foo")
    }

    @Test func decreaseIndentRemovesLeadingWhitespace() {
        let system = support.makeSystem(text: "    foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.decreaseIndent()

        #expect(handled)
        #expect(system.textView.string == "foo")
    }

    @Test func sortLinesOnAnEmptyDocumentDoesNothing() {
        let system = support.makeSystem(text: "")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        #expect(system.sortLines() == false)
        #expect(system.dedupeLines() == false)
        #expect(system.trimTrailingWhitespace() == false)
        #expect(system.textView.string == "")
    }
}
