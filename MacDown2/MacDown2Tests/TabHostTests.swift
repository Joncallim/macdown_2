import AppKit
@testable import MacDown2
import Testing

/// Review pass 1: a non-document key window (Settings, About, the welcome window, a panel) was
/// used as the tab host for a new document.
@MainActor
struct TabHostTests {
    @Test func aPlainWindowIsNotATabHost() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        #expect(WindowCoordinator.tabHost(window) == nil)
    }

    @Test func aPanelIsNotATabHost() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        panel.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        #expect(WindowCoordinator.tabHost(panel) == nil)
    }

    @Test func noWindowMeansNoHost() {
        #expect(WindowCoordinator.tabHost(nil) == nil)
    }

    @Test func theFirstRunWindowIsNotATabHost() {
        let controller = FirstRunWindowController(onStartWriting: {}, onOpenSample: {}, onClose: {})
        #expect(WindowCoordinator.tabHost(controller.window) == nil)
    }
}
