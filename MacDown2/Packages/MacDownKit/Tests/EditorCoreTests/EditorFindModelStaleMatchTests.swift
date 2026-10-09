import AppKit
@testable import EditorCore
import Foundation
import Testing
import TextSearch

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
        #expect(model.matchesAreCurrent(forLiveText: text))
        #expect(!model.matchesAreCurrent(forLiveText: text + "xyz"))
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
        #expect(!model.matchesAreCurrent(forLiveText: system.text))
    }
}

/// Tenth review R10-02 / R10-05.
@MainActor
struct EditorFindModelExactIdentityTests {
    @Test func aCanonicallyEqualButByteDistinctChangeMakesTheMatchesStale() async {
        let model = EditorFindModel(query: "\u{00C5}")
        model.options = SearchOptions(isCaseSensitive: true)
        let before = "\u{00C5} foo"
        await model.updateMatches(in: before)
        #expect(model.matches.count == 1)
        let after = "\u{212B} foo" // canonically equal to `before`, one UTF-16 unit, different text

        #expect(before == after)
        #expect(model.matchesAreCurrent(forLiveText: before))
        #expect(!model.matchesAreCurrent(forLiveText: after))
        #expect(ExactTextFingerprint(before) != ExactTextFingerprint(after))
    }

    @Test func aSameLengthEditIsNotCurrent() async {
        let model = EditorFindModel(query: "foo")
        await model.updateMatches(in: "abc foo")

        #expect(!model.matchesAreCurrent(forLiveText: "abc bar"))
    }

    @Test func cancellingAPendingSearchStopsItAndDiscardsItsResult() async {
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        await model.updateMatches(in: "plain")
        let previous = model.matches
        let pathological = String(repeating: "a", count: 40) + "!"
        let search = Task { await model.updateMatches(in: pathological) }
        while !model.isSearching {
            await Task.yield()
        }

        model.cancelPendingSearch()
        let published = await search.value

        #expect(!published)
        #expect(!model.isSearching)
        #expect(model.matches == previous)
    }
}
