import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 9: Find's matches are recomputed only when SwiftUI reports a text change, which marked-text (IME /
/// dead-key) edits never post. Replace All clicked during a composition (or in the click that commits it) wrote the
/// transaction at the old offsets: `abc foo⏎def foo` became `にほんabarfoo⏎dbarfoo`.
@MainActor
struct EditorFindModelStaleMatchTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func matchesAreCurrentOnlyForTheLengthTheyWereComputedAgainst() async {
        let model = EditorFindModel(query: "foo")
        let text = "abc foo\ndef foo"
        await model.updateMatches(in: text)

        #expect(model.matches.count == 2)
        #expect(model.matchesAreCurrent(forLiveLength: text.utf16.count))
        #expect(!model.matchesAreCurrent(forLiveLength: text.utf16.count + 3))
    }

    @Test func aMarkedTextCompositionMakesTheMatchesStaleAndBlocksCommandEdits() async {
        let system = support.makeSystem(text: "abc foo\ndef foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let model = EditorFindModel(query: "foo")
        await model.updateMatches(in: system.text)
        system.selectedRange = NSRange(location: 0, length: 0)

        system.textView.setMarkedText(
            "にほん",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(!system.canApplyCommandEdit)
        let live = system.textView.textStorage?.length ?? 0
        #expect(!model.matchesAreCurrent(forLiveLength: live))
    }
}
