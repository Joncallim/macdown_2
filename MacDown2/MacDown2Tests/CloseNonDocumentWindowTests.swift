import AppKit
@testable import MacDown2
import Testing

/// ⌘W was bound to "Close Tab" and disabled whenever the key window was not a document window, so Settings,
/// About and the welcome window could not be closed from the keyboard.
@MainActor
struct CloseNonDocumentWindowTests {
    @Test func aClosableWindowCanBeClosedWithCommandW() {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        #expect(WindowCoordinator.isCloseableNonDocumentWindow(window))
    }

    @Test func noWindowOrANonClosableOneCannot() {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        #expect(!WindowCoordinator.isCloseableNonDocumentWindow(window))
        #expect(!WindowCoordinator.isCloseableNonDocumentWindow(nil))
    }
}
