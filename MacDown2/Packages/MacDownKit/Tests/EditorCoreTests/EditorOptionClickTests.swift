import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3b-ii — Option-click add/remove caret (§6.10).
@MainActor
@Suite("EditorTextSystem Option-click (Slice 3b-ii)")
struct EditorOptionClickTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: - `toggleSecondaryCaret(at:)` (pure logic, no real click)

    @Test func addsASecondaryCaretWhenNoneExistsAtThatOffset() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3)

        let handled = system.toggleSecondaryCaret(at: 8)

        #expect(handled)
        #expect(system.selectionSet.isMultiple)
        #expect(system.selectionSet.ranges.contains(NSRange(location: 8, length: 0)))
        // The original primary selection must survive untouched.
        #expect(system.selectionSet.ranges.contains(NSRange(location: 0, length: 3)))
    }

    @Test func removesAnExistingSecondaryCaretAtTheSameOffsetToggle() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3)
        system.toggleSecondaryCaret(at: 8)
        #expect(system.selectionSet.isMultiple, "fixture must actually hold a secondary caret before toggling it off")

        let handled = system.toggleSecondaryCaret(at: 8)

        #expect(handled)
        #expect(!system.selectionSet.isMultiple)
        #expect(system.selectionSet.primaryRange == NSRange(location: 0, length: 3))
    }

    @Test func neverRemovesTheLastRemainingCaret() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 5, length: 0)

        // Toggling at the primary's own (only) location must not empty the
        // selection set -- `EditorSelectionSet.removeRange(at:)`'s own
        // "never empty" invariant, exercised through this call site.
        let handled = system.toggleSecondaryCaret(at: 5)

        #expect(handled)
        #expect(system.selectionSet.count == 1)
        #expect(system.selectionSet.primaryRange == NSRange(location: 5, length: 0))
    }

    @Test func outOfBoundsOffsetIsRejected() {
        let system = support.makeSystem(text: "short")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        #expect(!system.toggleSecondaryCaret(at: -1))
        #expect(!system.toggleSecondaryCaret(at: 999))
        #expect(!system.selectionSet.isMultiple, "a rejected toggle must not mutate the selection")
    }

    @Test func addingASecondCaretIsOneMoreThanAThirdDistinctOffset() {
        // Adversarial: three distinct carets accumulate correctly, not just
        // two.
        let system = support.makeSystem(text: "one two three four five")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        system.toggleSecondaryCaret(at: 8)
        system.toggleSecondaryCaret(at: 16)

        #expect(system.selectionSet.count == 3)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 8, length: 0),
            NSRange(location: 16, length: 0),
        ])
    }

    // MARK: - Real `mouseDown(with:)` (a genuine, synthesized NSEvent)

    private struct Mounted {
        let system: EditorTextSystem
        let textView: EditorTextView
        let window: NSWindow
    }

    private func mount(text: String) throws -> Mounted {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        let textView = try #require(system.textView as? EditorTextView)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scrollView.documentView = textView
        system.scrollView = scrollView
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        textView.layoutSubtreeIfNeeded()
        return Mounted(system: system, textView: textView, window: window)
    }

    /// Builds a real, synthetic Option-click `NSEvent` targeting `offset`,
    /// by round-tripping through `firstRect(forCharacterRange:)` (already
    /// confirmed correct in `EditorSecondaryCaretTests`) to find that
    /// offset's screen position, then converting back to window space --
    /// the exact inverse of what `mouseDown(with:)` itself does with a real
    /// click, so it exercises the real, full point-to-offset resolution
    /// path rather than assuming it.
    private func optionClickEvent(at offset: Int, in mounted: Mounted) throws -> NSEvent {
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let screenRect = mounted.textView.firstRect(
            forCharacterRange: NSRange(location: offset, length: 0),
            actualRange: &actualRange
        )
        let screenPoint = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let windowPoint = mounted.window.convertPoint(fromScreen: screenPoint)
        return try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: mounted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test func aRealOptionClickAddsASecondaryCaretAtTheClickedCharacter() throws {
        let mounted = try mount(text: "hello world\nsecond line")
        defer { mounted.window.orderOut(nil) }
        mounted.system.selectedRange = NSRange(location: 0, length: 0)

        let event = try optionClickEvent(at: 15, in: mounted)
        mounted.textView.mouseDown(with: event)

        #expect(mounted.system.selectionSet.isMultiple)
        #expect(mounted.system.selectionSet.ranges.contains(NSRange(location: 15, length: 0)))
    }

    @Test func aRealOptionClickOnAnExistingSecondaryCaretRemovesIt() throws {
        let mounted = try mount(text: "hello world\nsecond line")
        defer { mounted.window.orderOut(nil) }
        mounted.system.selectedRange = NSRange(location: 0, length: 0)
        mounted.system.toggleSecondaryCaret(at: 15)
        #expect(mounted.system.selectionSet.isMultiple)

        let event = try optionClickEvent(at: 15, in: mounted)
        mounted.textView.mouseDown(with: event)

        #expect(!mounted.system.selectionSet.isMultiple)
    }

    // A "plain click (no Option) falls through to super.mouseDown(_:) and
    // leaves the selection single" case is deliberately NOT exercised via a
    // real `mouseDown(with:)` call here: found empirically that
    // `NSTextView.mouseDown(with:)`'s real implementation enters an internal
    // modal event-tracking loop (waiting for the matching `mouseUp`/drag
    // events a real click's own event stream would supply) that hangs
    // indefinitely against one synthetic event with no real event queue
    // behind it in this headless test process -- confirmed by this exact
    // test hanging past the test runner's own timeout during this slice's
    // development. The override's own logic (`guard` on `.option` before
    // doing anything) is simple enough that `outOfBoundsOffsetIsRejected`'s
    // sibling coverage of the toggle logic itself, plus a plain code read,
    // is adequate; forcing a real native click through in a test is not
    // worth the risk of a hanging test suite.
}
