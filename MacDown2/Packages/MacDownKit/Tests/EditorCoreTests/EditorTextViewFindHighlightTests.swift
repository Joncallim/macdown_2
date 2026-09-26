import AppKit
@testable import EditorCore
import Testing

/// EPIC-22 §6.14, Slice 5a — `EditorTextSystem.setFindHighlights` forwarding
/// to `EditorTextView`. Verifies the forwarding/no-op-on-no-change logic
/// directly (mirroring `EditorTextView.showsInvisibles`'s own lack of a
/// pixel-level drawing test); actual paint output is exercised visually,
/// not asserted on here, matching `drawInvisibles`'s own precedent.
@MainActor
@Suite("EditorTextSystem.setFindHighlights (Slice 5a)")
struct EditorTextViewFindHighlightTests {
    private func makeSystem(text: String = "hello world") -> EditorTextSystem {
        EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
    }

    @Test("setFindHighlights forwards ranges and the current index to the text view")
    func forwardsRangesAndCurrentIndex() {
        let system = makeSystem()
        let ranges = [NSRange(location: 0, length: 5), NSRange(location: 6, length: 5)]

        system.setFindHighlights(ranges: ranges, currentIndex: 1)

        let textView = system.textView as? EditorTextView
        #expect(textView?.findHighlightRanges == ranges)
        #expect(textView?.currentFindMatchIndex == 1)
    }

    @Test("an empty ranges array with a nil index clears highlighting")
    func emptyRangesClearsHighlighting() {
        let system = makeSystem()
        system.setFindHighlights(ranges: [NSRange(location: 0, length: 5)], currentIndex: 0)

        system.setFindHighlights(ranges: [], currentIndex: nil)

        let textView = system.textView as? EditorTextView
        #expect(textView?.findHighlightRanges.isEmpty == true)
        #expect(textView?.currentFindMatchIndex == nil)
    }

    @Test("calling setFindHighlights with unchanged ranges/index is a harmless no-op")
    func unchangedCallIsANoOp() {
        let system = makeSystem()
        let ranges = [NSRange(location: 0, length: 5)]

        system.setFindHighlights(ranges: ranges, currentIndex: 0)
        system.setFindHighlights(ranges: ranges, currentIndex: 0)

        let textView = system.textView as? EditorTextView
        #expect(textView?.findHighlightRanges == ranges)
        #expect(textView?.currentFindMatchIndex == 0)
    }
}
