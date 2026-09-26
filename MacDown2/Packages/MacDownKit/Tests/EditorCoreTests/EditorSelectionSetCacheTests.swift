import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slices 3a/3b-i — `EditorTextSystem.selectionSet`'s
/// getter/setter/cache-invalidation contract, extracted from
/// `EditorMultiSelectionTests.swift` to keep that file under its line-count
/// limit (mirroring the established `DocumentEditorSplitView+EditorPane.swift`
/// precedent for splitting a file once it grows).
///
/// AppKit's `selectedRanges` has no concept of "primary," and (§6.9's
/// architecture-correction note) cannot hold more than one simultaneous
/// zero-length (bare-caret) range, or a mix of one with anything else, at
/// any spacing — confirmed empirically. `storedSelectionSet`'s own cache is
/// therefore the actual source of truth once a caret set AppKit cannot
/// corroborate is involved, and keeping that cache correct — not just
/// "returning the right value once, right after a write" — is what most of
/// this suite is about: an independent hostile review of PR #129 found, by
/// hand-tracing a real sequence, that a purely reactive staleness check
/// (only comparing the cache against live AppKit state at read time) is not
/// enough, since a later, unrelated selection change that happens to
/// coincide with the cache's own primary would satisfy that check and
/// wrongly resurrect stale state. The fix is proactive invalidation
/// (`EditorView.Coordinator.textViewDidChangeSelection` calling
/// `invalidateStoredSelectionSetIfStale()` on every selection-changed
/// notification the `selectionSet` setter itself did not post), which
/// `aCoincidentalReturnToTheOldPrimaryDoesNotResurrectAStaleSecondaryCaret`
/// and `documentReplacementClearsAStaleMultiSelectionCache` exercise
/// directly.
@MainActor
@Suite("EditorTextSystem.selectionSet cache (Slices 3a/3b-i)")
struct EditorSelectionSetCacheTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func selectionSetReflectsRealAppKitSelectedRanges() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let ranges = [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)]
        system.textView.selectedRanges = ranges.map { NSValue(range: $0) }

        #expect(system.selectionSet.ranges == ranges)
        #expect(system.selectionSet.isMultiple)
    }

    @Test func selectedRangeStaysConsistentWithSelectionSetsPrimary() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let ranges = [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)]
        system.textView.selectedRanges = ranges.map { NSValue(range: $0) }

        // AppKit's own singular accessor and this type's plural one must
        // agree on which range is "the" selection -- confirmed empirically
        // against a real mounted text view rather than assumed from
        // documentation alone, per this epic's established practice.
        #expect(system.selectedRange == system.selectionSet.primaryRange)
        #expect(system.selectedRange == ranges[0])
    }

    @Test func settingSelectionSetWritesBackToAppKit() {
        let system = support.makeSystem(text: "one two three four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let newSelection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)],
            primaryIndex: 1
        )
        system.selectionSet = newSelection

        #expect(system.textView.selectedRanges.map(\.rangeValue) == newSelection.ranges)
    }

    @Test func primaryIndexSurvivesAReadAfterWriteEvenWhenNotZero() {
        // The real bug this regression-guards: AppKit's own
        // `selectedRanges` has no concept of "primary" at all, so a naive
        // computed property that always reconstructs fresh from AppKit
        // would silently reset `primaryIndex` to 0 on every read -- found
        // by this exact test failing during Slice 3a's own development.
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 1
        )

        #expect(system.selectionSet.primaryRange == NSRange(location: 4, length: 3))
    }

    @Test func aNativeSelectionChangeInvalidatesTheCachedPrimaryIndex() {
        let system = support.makeSystem(text: "one two three four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 1
        )
        // Bypasses `selectionSet`'s setter entirely, simulating a native
        // AppKit-driven change (a click, arrow-key navigation) this type
        // did not mediate.
        system.textView.selectedRanges = [NSValue(range: NSRange(location: 8, length: 5))]

        #expect(system.selectionSet.primaryRange == NSRange(location: 8, length: 5))
        #expect(!system.selectionSet.isMultiple)
    }

    @Test func aCoincidentalReturnToTheOldPrimaryDoesNotResurrectAStaleSecondaryCaret() {
        // The real bug an independent hostile review of PR #129 found by
        // hand-tracing: after a multi-caret set collapses (AppKit can only
        // ever show the primary), a LATER, completely unrelated selection
        // change that happens to land back on that exact same primary
        // offset (a click, an outline jump-back, undo) must NOT resurrect
        // the stale secondary caret -- it has nothing to do with the user's
        // current intent, and `applyMultiCursorInsert` would otherwise fan
        // an ordinary keystroke out to it.
        let system = support.makeSystem(text: "one two three four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // A coordinator must be attached: the fix lives in
        // `textViewDidChangeSelection`, which only fires through a real
        // `NSTextViewDelegate`.
        system.textView.delegate = support.makeCoordinator(system: system)

        // A real selection as primary, plus a genuine bare CARET as
        // secondary -- the actual case AppKit cannot represent (unlike two
        // real, non-touching selections, which round-trip correctly and
        // are not what this test is about).
        let primary = NSRange(location: 0, length: 3)
        system.selectionSet = EditorSelectionSet(
            ranges: [primary, NSRange(location: 8, length: 0)],
            primaryIndex: 0
        )
        #expect(system.selectionSet.isMultiple, "fixture must actually hold a secondary caret before proceeding")

        // An unrelated native change (bypassing the `selectionSet` setter,
        // exactly like a real click would).
        system.textView.setSelectedRange(NSRange(location: 15, length: 0))
        // ...then back to the OLD primary's exact offset -- the
        // coincidental match that used to resurrect the secondary caret.
        system.textView.setSelectedRange(primary)

        #expect(
            !system.selectionSet.isMultiple,
            "a coincidental return to the old primary must not resurrect the stale secondary caret"
        )
    }

    @Test func documentReplacementClearsAStaleMultiSelectionCache() {
        // `setText`'s own caret always ends up wherever AppKit puts it after
        // a plain `.string =` reassignment (empirically: the new document's
        // end), which never coincides with a stale cached primary on its
        // own -- meaning a naive version of this test would pass even
        // without `setText`'s explicit `storedSelectionSet = nil` reset,
        // since the getter's pre-existing reactive fallback already
        // invalidates a cache whose primary no longer matches live AppKit
        // state (found by a second, focused re-review of this fix). Using
        // `replaceTextFromExternal` instead makes the coincidence
        // deterministic: its `snapshot.selectedRange` explicitly controls
        // where the post-replacement caret lands, so it can be set to the
        // EXACT same offset as the stale cached primary -- the one
        // combination that actually exercises the explicit reset rather
        // than merely happening to be covered by the reactive fallback too.
        let system = support.makeSystem(text: "one two three four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let stalePrimary = NSRange(location: 0, length: 0)
        system.selectionSet = EditorSelectionSet(
            ranges: [stalePrimary, NSRange(location: 8, length: 3)],
            primaryIndex: 0
        )
        #expect(system.selectionSet.isMultiple)

        system.replaceTextFromExternal(
            "brand new document",
            preserving: EditorViewportSnapshot(selectedRange: stalePrimary, scrollOffset: 0),
            clearUndo: false
        )

        #expect(
            !system.selectionSet.isMultiple,
            "a whole-document replacement must never resurrect a stale multi-selection cache from the previous document"
        )
    }
}
