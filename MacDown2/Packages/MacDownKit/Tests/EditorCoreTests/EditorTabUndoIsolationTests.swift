import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: tabs of one window shared the window's `UndoManager`, so Cmd-Z in tab B
/// undid tab A's edit (and the hidden tab's line index went stale).
@MainActor
struct EditorTabUndoIsolationTests {
    private func makeSystem(_ text: String) -> EditorTextSystem {
        EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
    }

    @Test func eachTabHasItsOwnUndoManagerEvenInTheSameWindow() {
        let first = makeSystem("AAAA")
        let second = makeSystem("BBBB")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        window.contentView = first.textView
        first.textView.insertText("x\ny\nz", replacementRange: NSRange(location: 4, length: 0))
        window.contentView = second.textView

        #expect(first.undoManager !== second.undoManager)
        #expect(first.textView.undoManager === first.undoManager)
        #expect(second.textView.undoManager === second.undoManager)
        // Undo in the tab being shown does nothing to the other tab's text...
        second.undoManager.undo()
        #expect(first.text == "AAAAx\ny\nz")
        // ...and undo in its own tab still works.
        first.undoManager.undo()
        #expect(first.text == "AAAA")
    }
}
