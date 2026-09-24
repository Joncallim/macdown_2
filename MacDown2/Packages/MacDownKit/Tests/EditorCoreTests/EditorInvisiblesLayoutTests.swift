@testable import EditorCore
import Testing

@Suite("EditorInvisiblesLayout")
struct EditorInvisiblesLayoutTests {
    @Test func emptyTextHasNoMarkers() {
        #expect(EditorInvisiblesLayout.markers(in: "") == [])
    }

    @Test func plainTextWithNoInvisiblesHasNoMarkers() {
        #expect(EditorInvisiblesLayout.markers(in: "hello") == [])
    }

    @Test func detectsASingleSpace() {
        let markers = EditorInvisiblesLayout.markers(in: "a b")
        #expect(markers == [.init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.spaceGlyph)])
    }

    @Test func detectsMultipleConsecutiveSpaces() {
        let markers = EditorInvisiblesLayout.markers(in: "a  b")
        #expect(markers == [
            .init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.spaceGlyph),
            .init(localUTF16Offset: 2, glyph: EditorInvisiblesLayout.spaceGlyph),
        ])
    }

    @Test func detectsATab() {
        let markers = EditorInvisiblesLayout.markers(in: "a\tb")
        #expect(markers == [.init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.tabGlyph)])
    }

    @Test func detectsALineFeedAsOneMarker() {
        let markers = EditorInvisiblesLayout.markers(in: "a\n")
        #expect(markers == [.init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.returnGlyph)])
    }

    @Test func detectsABareCarriageReturnAsOneMarker() {
        let markers = EditorInvisiblesLayout.markers(in: "a\r")
        #expect(markers == [.init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.returnGlyph)])
    }

    @Test func detectsACRLFPairAsExactlyOneMarkerNotTwo() {
        let markers = EditorInvisiblesLayout.markers(in: "a\r\nb")
        #expect(markers == [.init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.returnGlyph)])
        // The marker for the CRLF pair, plus "b" starting right after both
        // units -- confirms the pair was consumed as a whole, not left with
        // a dangling second marker for the \n.
        #expect(markers.count == 1)
    }

    @Test func detectsMixedSpacesTabsAndLineEndingsTogether() {
        let markers = EditorInvisiblesLayout.markers(in: " \ta\r\nb ")
        #expect(markers == [
            .init(localUTF16Offset: 0, glyph: EditorInvisiblesLayout.spaceGlyph),
            .init(localUTF16Offset: 1, glyph: EditorInvisiblesLayout.tabGlyph),
            .init(localUTF16Offset: 3, glyph: EditorInvisiblesLayout.returnGlyph),
            .init(localUTF16Offset: 6, glyph: EditorInvisiblesLayout.spaceGlyph),
        ])
    }

    @Test func nonBreakingSpaceIsNotMarked() {
        // Deliberately out of scope for this slice (§6.8) -- confirms the
        // scope boundary is real, not accidentally broader than intended.
        #expect(EditorInvisiblesLayout.markers(in: "a\u{00A0}b") == [])
    }

    @Test func aLineOfOnlyTabsProducesOneMarkerPerTab() {
        let markers = EditorInvisiblesLayout.markers(in: "\t\t\t")
        #expect(markers.count == 3)
        #expect(markers.allSatisfy { $0.glyph == EditorInvisiblesLayout.tabGlyph })
        #expect(markers.map(\.localUTF16Offset) == [0, 1, 2])
    }

    @Test func markersSurviveSurrogatePairContentWithoutMisalignment() {
        // 😀 is a 2-UTF-16-unit surrogate pair; the trailing space must
        // still be found at the correct UTF-16 offset (3), not offset 2
        // (which would be the case if the scan miscounted the emoji as one
        // unit).
        let markers = EditorInvisiblesLayout.markers(in: "😀 b")
        #expect(markers == [.init(localUTF16Offset: 2, glyph: EditorInvisiblesLayout.spaceGlyph)])
    }
}
