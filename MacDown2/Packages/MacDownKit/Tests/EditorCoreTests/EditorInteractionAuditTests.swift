import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Cross-feature audit findings: IME safety of editing commands, out-of-bounds
/// cached selections after a transform, and primary-selection stability.
@MainActor
@Suite("Interaction audit regressions")
struct EditorInteractionAuditTests {
    private let support = EditingAssistIntegrationSupport.self

    private func mounted(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        system.textView.delegate = support.makeCoordinator(system: system)
        return (system, window)
    }

    // MARK: - IME composition

    @Test func editingCommandsFailOpenDuringAnIMEComposition() {
        let (system, window) = mounted("b \na\nc")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 6, length: 0)
        system.textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: 6, length: 0)
        )
        let before = system.textView.string

        #expect(!system.convertLineEndings(to: .crlf))
        #expect(!system.increaseIndent())
        #expect(!system.trimTrailingWhitespace())
        #expect(!system.sortLines())
        #expect(!system.moveLinesUp())
        #expect(!system.toggleComment())

        #expect(system.textView.hasMarkedText())
        #expect(system.textView.string == before)
    }

    @Test func theSameCommandsRunNormallyWithoutAComposition() {
        let (system, window) = mounted("b \na")
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 4)

        #expect(system.trimTrailingWhitespace())
        #expect(system.textView.string == "b\na")
    }

    // MARK: - Cached selection after Move Line

    @Test func moveLineDownLeavesNoOutOfBoundsCachedSelection() {
        let (system, window) = mounted("a\nb\nc\nd")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)],
            primaryIndex: 0
        )

        #expect(system.moveLinesDown())

        let length = (system.textView.string as NSString).length
        #expect(system.selectionSet.ranges.allSatisfy { NSMaxRange($0) <= length })
        system.textView.deleteBackward(nil)
        #expect(system.textView.string != "b\na\nd\nc")
    }

    @Test func clampingLeavesAnInBoundsSelectionUntouched() {
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 2), NSRange(location: 3, length: 1)],
            primaryIndex: 1
        )

        #expect(EditorTextSystem.clamped(selection, toLength: 10) == selection)
    }

    // MARK: - Primary selection

    @Test func aTouchingCaretDoesNotStealPrimaryFromTheSelectionItAbuts() {
        var set = EditorSelectionSet(single: NSRange(location: 3, length: 2))
        set.addRange(NSRange(location: 3, length: 0), makePrimary: false)
        #expect(set.primaryRange == NSRange(location: 3, length: 2))

        let direct = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 3, length: 2)],
            primaryIndex: 1
        )
        #expect(direct.primaryRange == NSRange(location: 3, length: 2))
    }

    @Test func aCaretStillBecomesPrimaryWhenItIsTheOneAskedFor() {
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 3, length: 2)],
            primaryIndex: 0
        )
        #expect(set.primaryRange == NSRange(location: 3, length: 0))
    }
}

/// Tenth review R10-08: Bold/Italic/Heading and Add Cursor Above/Below were outside the common IME guard.
@MainActor
struct EditorCompositionBoundaryTests {
    private let support = EditingAssistIntegrationSupport.self

    private func composing(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = support.makeMarkdownSystem(text: text)
        let window = support.mountInWindow(system)
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        system.textView.setMarkedText(
            "x",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: (text as NSString).length, length: 0)
        )
        return (system, window)
    }

    @Test func markdownFormattingCommandsFailOpenDuringAComposition() {
        let (system, window) = composing("a\nb\nc")
        defer { window.orderOut(nil) }
        let before = system.textView.string

        #expect(!system.performMarkdownCommand(.bold))
        #expect(!system.performMarkdownCommand(.italic))
        #expect(!system.performMarkdownCommand(.heading(level: 2)))

        #expect(system.textView.hasMarkedText())
        #expect(system.textView.string == before)
    }

    @Test func addCursorCommandsFailOpenDuringAComposition() {
        let (system, window) = composing("a\nb\nc")
        defer { window.orderOut(nil) }

        #expect(!system.addCursorAbove())
        #expect(!system.addCursorBelow())
        #expect(!system.selectionSet.isMultiple)
    }

    @Test func theSameCommandsStillWorkWithoutAComposition() {
        let system = support.makeMarkdownSystem(text: "a\nb\nc")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 1)

        #expect(system.addCursorBelow())
        #expect(system.selectionSet.isMultiple)
    }
}
