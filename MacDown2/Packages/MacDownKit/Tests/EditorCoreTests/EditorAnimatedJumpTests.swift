import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("EditorTextSystem animated jump")
struct EditorAnimatedJumpTests {
    private func makeSystem(text: String = "") -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
    }

    /// The outline sidebar's jump animates instead of snapping instantly.
    /// Selection must still be set synchronously (so e.g. typing right after
    /// a jump lands in the right place, without waiting on the animation).
    ///
    /// The animation's own end state is deliberately NOT asserted here:
    /// headless tests have no real display driving `NSAnimationContext`, so
    /// there is nothing reliable to wait for. What the animation scrolls
    /// *to* is verified directly below instead, via the same layout-fragment
    /// lookup `revealSelection(animated:)` uses to compute that target.
    @Test("revealSelection(animated:) sets selection synchronously")
    func revealSelectionAnimatedSetsSelectionImmediately() {
        let lineText = "The quick brown fox jumps over the lazy dog.\n"
        let text = String(repeating: lineText, count: 400)
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
        scrollView.layoutSubtreeIfNeeded()
        system.syncFrameHeightToContent()

        let targetOffset = 299 * lineText.utf16.count
        system.revealSelection(
            utf16Range: NSRange(location: targetOffset, length: 1),
            flash: false,
            animated: true
        )

        #expect(
            system.selectedRange.location == targetOffset,
            "Selection must be set synchronously, not deferred until the scroll animation completes"
        )
    }

    // Regression guard for the jump animation's target computation, which
    // `revealSelection(animated:)` cannot be observed exercising end-to-end
    // in a headless test (see above) — this pins the same fragment lookup
    // directly. A later line's target must resolve strictly further down
    // the document, monotonically, the same property `topVisibleUTF16Offset`'s
    // fragment-lookup fix depends on in the opposite direction.
    @Test("layoutFragmentFrame(atUTF16Location:) resolves later locations further down the document")
    func layoutFragmentFrameIsMonotonicInDocumentOrder() {
        let lineText = "The quick brown fox jumps over the lazy dog.\n"
        let text = String(repeating: lineText, count: 400)
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
        scrollView.layoutSubtreeIfNeeded()
        system.syncFrameHeightToContent()

        let lineUTF16Length = lineText.utf16.count
        let earlyFrame = system.layoutFragmentFrame(atUTF16Location: 9 * lineUTF16Length)
        let lateFrame = system.layoutFragmentFrame(atUTF16Location: 299 * lineUTF16Length)

        #expect(earlyFrame != nil)
        #expect(lateFrame != nil)
        if let earlyFrame, let lateFrame {
            #expect(
                lateFrame.minY > earlyFrame.minY,
                "Line 300's target must resolve further down the document than line 10's"
            )
        }
    }
}
