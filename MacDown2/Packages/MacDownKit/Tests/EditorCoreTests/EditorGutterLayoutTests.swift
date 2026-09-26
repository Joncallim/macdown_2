@testable import EditorCore
import Foundation
import Testing

@Suite("EditorGutterLayout")
struct EditorGutterLayoutTests {
    @Test func oneLabelPerLineForNonWrappedFragments() {
        let lineIndex = EditorLineIndex(text: "aaa\nbbb\nccc")
        // One fragment per line, each starting exactly at that line's start.
        let fragments: [(utf16Offset: Int, minY: CGFloat)] = [
            (0, 0),
            (4, 20),
            (8, 40),
        ]
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: lineIndex)
        #expect(labels == [
            GutterLineLabel(lineNumber: 1, minY: 0),
            GutterLineLabel(lineNumber: 2, minY: 20),
            GutterLineLabel(lineNumber: 3, minY: 40),
        ])
    }

    @Test func wrappedContinuationFragmentsAreSkipped() {
        // Line 1 is "aaaaaaaaaa" (10 chars) wrapping into two fragments;
        // line 2 is "bbb". Only the fragment starting AT a recorded line
        // start gets a label -- the wrap-continuation fragment (starting
        // mid-line-1, at offset 5) must not produce a second "1" label.
        let lineIndex = EditorLineIndex(text: "aaaaaaaaaa\nbbb")
        let fragments: [(utf16Offset: Int, minY: CGFloat)] = [
            (0, 0), // line 1, first fragment
            (5, 15), // line 1, wrapped continuation -- no label
            (11, 30), // line 2, first fragment
        ]
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: lineIndex)
        #expect(labels == [
            GutterLineLabel(lineNumber: 1, minY: 0),
            GutterLineLabel(lineNumber: 2, minY: 30),
        ])
    }

    @Test func emptyFragmentListProducesNoLabels() {
        let lineIndex = EditorLineIndex(text: "a\nb")
        #expect(EditorGutterLayout.labels(for: [], lineIndex: lineIndex).isEmpty)
    }

    @Test func singleEmptyDocumentLineProducesOneLabel() {
        let lineIndex = EditorLineIndex(text: "")
        let labels = EditorGutterLayout.labels(for: [(0, 0)], lineIndex: lineIndex)
        #expect(labels == [GutterLineLabel(lineNumber: 1, minY: 0)])
    }

    @Test func outOfRangeOffsetIsIgnoredRatherThanCrashing() {
        // Adversarial: a fragment offset past the document's own recorded
        // length (e.g. a stale enumeration racing a concurrent edit) must
        // be dropped, never indexed out of bounds.
        let lineIndex = EditorLineIndex(text: "abc")
        let fragments: [(utf16Offset: Int, minY: CGFloat)] = [(0, 0), (999, 50)]
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: lineIndex)
        #expect(labels == [GutterLineLabel(lineNumber: 1, minY: 0)])
    }

    @Test func consecutiveEmptyLinesEachGetTheirOwnLabel() {
        let lineIndex = EditorLineIndex(text: "a\n\n\nb")
        let fragments: [(utf16Offset: Int, minY: CGFloat)] = [
            (0, 0),
            (2, 10),
            (3, 20),
            (4, 30),
        ]
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: lineIndex)
        #expect(labels.map(\.lineNumber) == [1, 2, 3, 4])
    }
}
