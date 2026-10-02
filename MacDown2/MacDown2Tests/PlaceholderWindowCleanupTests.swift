import AppKit
@testable import MacDown2
import Testing

/// Review pass 1: the launch-time placeholder cleanup closed the first-run
/// welcome window ~100 ms after it appeared, completing onboarding unseen.
@MainActor
struct PlaceholderWindowCleanupTests {
    @Test func theFirstRunWelcomeWindowIsNotAPlaceholder() throws {
        let controller = FirstRunWindowController(onStartWriting: {}, onOpenSample: {}, onClose: {})
        let window = try #require(controller.window)
        #expect(!AppDelegate.isSwiftUIPlaceholder(window))
    }

    @Test func aWindowWithAForeignDelegateIsAPlaceholder() {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true
        )
        #expect(AppDelegate.isSwiftUIPlaceholder(window))
    }
}
