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

    // Regression: `topVisibleUTF16Offset` previously read a view-local point
    // through `NSTextInputClient.characterIndex(for:)`, which expects
    // *screen* coordinates — silently wrong for any real scroll position, but
    // easy to miss because bounds-only assertions (above) pass either way.
    // Hosting the scroll view in a real window and scrolling to a known deep
    // line makes the coordinate space observable: the reported offset must
    // land near the requested line, not stay near the top (a screen-space
    // hit-test against a small view-local point tends to land outside the
    // window entirely, which `characterIndexForInsertion`/`characterIndex`
    // both report as `NSNotFound`, mapped to the misleading "0" this test
    // rules out).
    @Test("topVisibleUTF16Offset reflects a real scroll position, not just its bounds")
    func topOffsetReflectsARealScrollPosition() {
        let lineText = "The quick brown fox jumps over the lazy dog.\n"
        let lineCount = 400
        let text = String(repeating: lineText, count: lineCount)
        let system = makeSystem(text: text)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        window.contentView = scrollView

        let lineUTF16Length = lineText.utf16.count
        system.textView.frame = NSRect(
            x: 0, y: 0,
            width: 400,
            height: CGFloat(lineCount * 20)
        )
        scrollView.layoutSubtreeIfNeeded()

        // Scroll to a line deep in the document, far past the first screen.
        let targetLine = 300
        let targetOffset = (targetLine - 1) * lineUTF16Length
        system.scrollToVisible(utf16Range: NSRange(location: targetOffset, length: 1))

        let reportedOffset = system.topVisibleUTF16Offset
        let reportedLine = reportedOffset / lineUTF16Length + 1

        // `scrollRangeToVisible` scrolls the minimum distance, so the reported
        // top line may sit somewhat before the requested one (the viewport
        // holds several lines) — but it must be deep in the document, not
        // stuck near line 1 (the failure mode of the coordinate-space bug)
        // and not past the requested line (scrolling into view cannot
        // overshoot past the target).
        #expect(
            reportedLine > lineCount / 4,
            "Expected a line well past the start of the document, got \(reportedLine)"
        )
        #expect(
            reportedLine <= targetLine,
            "Expected the top line at or before the requested line \(targetLine), got \(reportedLine)"
        )
    }
}
