import Foundation
import Testing
import Workspace

@Suite("PreviewLayoutMode")
struct PreviewLayoutModeTests {
    @Test func defaultModeIsSplitHalf() {
        #expect(PreviewLayoutMode.defaultMode == .split(fraction: 0.5))
    }

    @Test func splitShowsEditorAndPreview() {
        let mode = PreviewLayoutMode.split(fraction: 0.5)
        #expect(mode.showsEditor)
        #expect(mode.showsPreview)
    }

    @Test func editorOnlyShowsEditorOnly() {
        let mode = PreviewLayoutMode.editorOnly
        #expect(mode.showsEditor)
        #expect(!mode.showsPreview)
    }

    @Test func previewOnlyShowsPreviewOnly() {
        let mode = PreviewLayoutMode.previewOnly
        #expect(!mode.showsEditor)
        #expect(mode.showsPreview)
    }

    @Test func clampingPreservesInRangeFraction() {
        let mode = PreviewLayoutMode.split(fraction: 0.3)
        #expect(mode.clamped() == .split(fraction: 0.3))
    }

    @Test func clampingRaisesTooSmallFraction() {
        let mode = PreviewLayoutMode.split(fraction: 0.05)
        #expect(mode.clamped() == .split(fraction: 0.15))
    }

    @Test func clampingLowersTooLargeFraction() {
        let mode = PreviewLayoutMode.split(fraction: 0.95)
        #expect(mode.clamped() == .split(fraction: 0.85))
    }

    @Test func nonSplitModesUnchangedByClamping() {
        #expect(PreviewLayoutMode.editorOnly.clamped() == .editorOnly)
        #expect(PreviewLayoutMode.previewOnly.clamped() == .previewOnly)
    }

    @Test func modeIsCodableRoundTrippable() throws {
        let values: [PreviewLayoutMode] = [
            .editorOnly,
            .split(fraction: 0.3),
            .previewOnly,
        ]
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([PreviewLayoutMode].self, from: data)
        #expect(decoded == values)
    }
}
