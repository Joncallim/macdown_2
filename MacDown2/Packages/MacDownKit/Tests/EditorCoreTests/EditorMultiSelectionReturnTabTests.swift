import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 7: AppKit's `insertNewline:`/`insertTab:` pass an explicit replacement range for the primary selection
/// only, so with several selections the others were left in place (Return in LF documents) or never indented (Tab).
@MainActor
struct EditorMultiSelectionReturnTabTests {
    private let support = EditingAssistIntegrationSupport.self

    private struct Fixture {
        let system: EditorTextSystem
        let window: NSWindow
        let coordinator: EditorView.Coordinator
    }

    private func twoSelections(in text: String, _ first: NSRange, _ second: NSRange) -> Fixture {
        let system = support.makeMarkdownSystem(text: text)
        let window = support.mountInWindow(system)
        let coordinator = support.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(ranges: [first, second], primaryIndex: 0)
        return Fixture(system: system, window: window, coordinator: coordinator)
    }

    @Test func returnReplacesEverySelectionInAnLFDocument() {
        let fixture = twoSelections(in: "ab cd ef", NSRange(location: 0, length: 2), NSRange(location: 6, length: 2))
        defer { fixture.window.orderOut(nil) }

        let handled = fixture.coordinator.textView(
            fixture.system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled)
        #expect(fixture.system.text == "\n cd \n")
    }

    @Test func tabIndentsTheLineOfEverySelection() {
        let fixture = twoSelections(
            in: "one\ntwo\nthree", NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)
        )
        defer { fixture.window.orderOut(nil) }

        let handled = fixture.coordinator.textView(
            fixture.system.textView, doCommandBy: #selector(NSResponder.insertTab(_:))
        )

        #expect(handled)
        let lines = fixture.system.text.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] != "one" && lines[0].hasSuffix("one"))
        #expect(lines[1] == "two")
        #expect(lines[2] != "three" && lines[2].hasSuffix("three"))
    }

    @Test func aSingleSelectionStillFallsThroughToNativeReturn() {
        let system = support.makeMarkdownSystem(text: "ab cd")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 2)

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(!handled)
    }
}

/// Tenth review R10-06: the selection callback reported AppKit's topmost range, not the selection set's primary.
@MainActor
struct EditorSelectionCallbackPrimaryTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func theCallbackReportsThePrimaryRangeNotTheTopmostOne() {
        let system = support.makeMarkdownSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        var reported: [NSRange] = []
        coordinator.onSelectionChange = { reported.append($0) }

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)],
            primaryIndex: 1
        )
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))

        #expect(reported.last == NSRange(location: 8, length: 5))
    }
}
