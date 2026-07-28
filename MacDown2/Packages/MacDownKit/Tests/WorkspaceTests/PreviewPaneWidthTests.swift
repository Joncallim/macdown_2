import Foundation
import Testing
@testable import Workspace

@Suite("Preview pane widths")
struct PreviewPaneWidthTests {
    @Test func editorOnlyFillsTotalWidth() {
        #expect(PreviewPaneWidths.editorWidth(in: 1000, layout: .editorOnly) == 1000)
        #expect(PreviewPaneWidths.previewWidth(in: 1000, layout: .editorOnly) == 0)
    }

    @Test func previewOnlyFillsTotalWidth() {
        #expect(PreviewPaneWidths.editorWidth(in: 1000, layout: .previewOnly) == 0)
        #expect(PreviewPaneWidths.previewWidth(in: 1000, layout: .previewOnly) == 1000)
    }

    @Test func splitHonorsFraction() {
        let layout = PreviewLayoutMode.split(fraction: 0.25)
        #expect(PreviewPaneWidths.editorWidth(in: 1000, layout: layout) == 250)
        #expect(PreviewPaneWidths.previewWidth(in: 1000, layout: layout) == 749)
    }

    @Test func splitAtDefaultDividesEqually() {
        let layout = PreviewLayoutMode.split(fraction: 0.5)
        #expect(PreviewPaneWidths.editorWidth(in: 800, layout: layout) == 400)
        #expect(PreviewPaneWidths.previewWidth(in: 800, layout: layout) == 399)
    }

    @Test func negativeFractionClampsEditorToZero() {
        let layout = PreviewLayoutMode.split(fraction: -0.2)
        #expect(PreviewPaneWidths.editorWidth(in: 500, layout: layout) == 0)
        #expect(PreviewPaneWidths.previewWidth(in: 500, layout: layout) == 499)
    }

    @Test func oversizedFractionLeavesNoRoomForPreview() {
        let layout = PreviewLayoutMode.split(fraction: 1.5)
        #expect(PreviewPaneWidths.editorWidth(in: 600, layout: layout) == 900)
        #expect(PreviewPaneWidths.previewWidth(in: 600, layout: layout) == 0)
    }

    @Test func fractionalTotalWidthAccountsForDivider() {
        let layout = PreviewLayoutMode.split(fraction: 0.3333)
        let total = CGFloat(1000)
        let editor = PreviewPaneWidths.editorWidth(in: total, layout: layout)
        let preview = PreviewPaneWidths.previewWidth(in: total, layout: layout)
        #expect(editor == CGFloat(333.3))
        #expect(preview == CGFloat(665.7))
        #expect(editor + preview + dividerWidth == total)
    }
}
