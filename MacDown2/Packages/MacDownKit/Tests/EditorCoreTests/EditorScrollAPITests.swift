import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("EditorScrollAPI")
struct EditorScrollAPITests {
    private func makeSystem(text: String = "") -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
    }

    @Test("topVisibleUTF16Offset returns zero for a headless system")
    func headlessTopOffsetIsZero() {
        let system = makeSystem(text: "hello world")
        #expect(system.topVisibleUTF16Offset == 0)
    }

    @Test("topVisibleUTF16Offset stays within text bounds")
    func topOffsetIsWithinBounds() {
        let system = makeSystem(text: "line one\nline two\nline three")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        scrollView.layoutSubtreeIfNeeded()

        let offset = system.topVisibleUTF16Offset
        #expect(offset >= 0)
        #expect(offset <= system.text.utf16.count)
    }

    @Test("scrollToVisible accepts a valid range without crashing")
    func scrollToVisibleAcceptsValidRange() {
        let system = makeSystem(text: "one\ntwo\nthree")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView

        system.scrollToVisible(utf16Range: NSRange(location: 6, length: 3))
    }

    @Test("scrollToVisible keeps top offset within bounds")
    func scrollToVisibleKeepsTopOffsetValid() {
        let text = String(repeating: "The quick brown fox jumps.\n", count: 100)
        let system = makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 400, height: 4000)
        scrollView.layoutSubtreeIfNeeded()

        system.scrollToVisible(utf16Range: NSRange(
            location: text.utf16.count - 20,
            length: 10
        ))
        let after = system.topVisibleUTF16Offset

        // Without a real window the offset may stay at zero, but it must never
        // be out of bounds.
        #expect(after >= 0)
        #expect(after <= system.text.utf16.count)
    }
}
