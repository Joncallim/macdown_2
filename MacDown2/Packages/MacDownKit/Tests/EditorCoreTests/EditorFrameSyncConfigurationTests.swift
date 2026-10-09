import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Tenth review R10-03: `FrameSyncSignature` is (text length, width, edit revision), none of which a font, inset, line
/// height or wrap-mode change touches, so `syncFrameHeightToContent` reinstalled the old measured height without
/// calling the meter: too short after a larger font (end unreachable), too long after a smaller one.
@MainActor
struct EditorFrameSyncConfigurationTests {
    private func mountedSystem(text: String) -> EditorTextSystem {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        scrollView.layoutSubtreeIfNeeded()
        return system
    }

    @Test func aLargerFontAtUnchangedTextAndWidthGrowsTheFrame() {
        let text = String(repeating: "The quick brown fox jumps over the lazy dog.\n", count: 100)
        let system = mountedSystem(text: text)
        system.syncFrameHeightToContent()
        let smallHeight = system.textView.frame.height

        var larger = EditorConfiguration.default
        larger.font = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)
        system.apply(larger)
        system.syncFrameHeightToContent()

        #expect(
            system.textView.frame.height > smallHeight * 1.5,
            "frame \(system.textView.frame.height) vs \(smallHeight)"
        )
    }

    @Test func aSmallerFontAtUnchangedTextAndWidthShrinksTheFrame() {
        let text = String(repeating: "The quick brown fox jumps over the lazy dog.\n", count: 100)
        var large = EditorConfiguration.default
        large.font = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: large)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        scrollView.layoutSubtreeIfNeeded()
        system.syncFrameHeightToContent()
        let largeHeight = system.textView.frame.height

        var small = EditorConfiguration.default
        small.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        system.apply(small)
        system.syncFrameHeightToContent()

        #expect(
            system.textView.frame.height < largeHeight * 0.7,
            "frame \(system.textView.frame.height) vs \(largeHeight)"
        )
    }

    @Test func aLineHeightChangeAlsoReMeasures() {
        let text = String(repeating: "The quick brown fox jumps over the lazy dog.\n", count: 100)
        let system = mountedSystem(text: text)
        system.syncFrameHeightToContent()
        let before = system.textView.frame.height

        var airy = EditorConfiguration.default
        airy.lineHeightMultiple = 2.5
        system.apply(airy)
        system.syncFrameHeightToContent()

        #expect(system.textView.frame.height > before * 1.3)
    }
}
