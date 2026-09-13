import AppKit
import Foundation
import Math
import MathRendering
import Testing

/// Real, non-faked `ImageRenderer`/`SwiftUIMath` rendering — precedent for
/// this being reliable inside a plain SPM `.testTarget` (no app window/view
/// hierarchy) comes from `textual` 0.5.0's own test suite
/// (`TextBuilderTests.swift`, which calls `ImageRenderer(content:...)
/// .nsImage` the same way), found during this epic's independent
/// architecture review (epic-19-implementation.md §17 Slice 2).
@Suite("MathImageRenderer")
@MainActor
struct MathImageRendererTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1, pixelScale: 3
    )

    @Test func renderProducesDecodablePNGDataForValidInlineLatex() throws {
        let span = MathSpan(range: 0 ..< 5, style: .inline, latex: "x=1")
        let data = try MathImageRenderer.render(span: span, context: Self.context)

        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG magic bytes
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)
    }

    @Test func renderProducesDecodablePNGDataForValidDisplayLatex() throws {
        let span = MathSpan(range: 0 ..< 20, style: .display, latex: "\\frac{1}{2}+\\sqrt{2}")
        let data = try MathImageRenderer.render(span: span, context: Self.context)
        #expect(NSBitmapImageRep(data: data) != nil)
    }

    /// `ImageRenderer` rounds the view's point-sized layout to a whole pixel
    /// count independently at each scale (e.g. 10.33pt → 11px at 1x, but
    /// 30.99px → 31px, not 33px, at 3x) — real, observed rounding, not an
    /// exact multiple. This asserts "meaningfully larger, within rounding,"
    /// not bit-exact scaling.
    @Test func renderScalesPixelDimensionsByThePixelScale() throws {
        let span = MathSpan(range: 0 ..< 5, style: .inline, latex: "x")
        let unscaled = ExportMathRenderContext(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 1)
        let scaled = ExportMathRenderContext(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 3)

        let unscaledData = try MathImageRenderer.render(span: span, context: unscaled)
        let scaledData = try MathImageRenderer.render(span: span, context: scaled)

        let unscaledBitmap = try #require(NSBitmapImageRep(data: unscaledData))
        let scaledBitmap = try #require(NSBitmapImageRep(data: scaledData))
        let widthTolerance = 2
        let heightTolerance = 2
        #expect(abs(scaledBitmap.pixelsWide - unscaledBitmap.pixelsWide * 3) <= widthTolerance)
        #expect(abs(scaledBitmap.pixelsHigh - unscaledBitmap.pixelsHigh * 3) <= heightTolerance)
    }

    /// The one failure signal available (epic-19-implementation.md §2.1):
    /// malformed LaTeX measures to zero typographic bounds rather than
    /// throwing a structured parse error.
    @Test func renderThrowsCouldNotTypesetForMalformedLatex() {
        let span = MathSpan(range: 0 ..< 10, style: .inline, latex: "\\frac{1}{")
        #expect(throws: MathRenderError.couldNotTypeset) {
            _ = try MathImageRenderer.render(span: span, context: Self.context)
        }
    }

    @Test func renderThrowsCouldNotTypesetForEmptyLatex() {
        let span = MathSpan(range: 0 ..< 2, style: .inline, latex: "")
        #expect(throws: MathRenderError.couldNotTypeset) {
            _ = try MathImageRenderer.render(span: span, context: Self.context)
        }
    }

    /// `isRenderable` is what `MathPreviewPreprocessor` (app target) uses to
    /// decide whether Preview should flag a span (epic-19-implementation.md
    /// §6.1) — it must agree exactly with what `render` would do, since both
    /// consult the same shared bounds check.
    @Test func isRenderableAgreesWithRenderForValidLatex() {
        let span = MathSpan(range: 0 ..< 5, style: .inline, latex: "x=1")
        #expect(MathImageRenderer.isRenderable(span))
    }

    @Test func isRenderableAgreesWithRenderForMalformedLatex() {
        let span = MathSpan(range: 0 ..< 10, style: .inline, latex: "\\frac{1}{")
        #expect(!MathImageRenderer.isRenderable(span))
    }

    @Test func isRenderableIsFalseForEmptyLatex() {
        let span = MathSpan(range: 0 ..< 2, style: .display, latex: "")
        #expect(!MathImageRenderer.isRenderable(span))
    }

    @Test func isRenderableIsTrueForADisplayEquation() {
        let span = MathSpan(range: 0 ..< 20, style: .display, latex: "\\frac{1}{2}+\\sqrt{2}")
        #expect(MathImageRenderer.isRenderable(span))
    }

    /// Export's half of the Preview/Export parity requirement
    /// (epic-19-implementation.md §2.1, §7.1): every case in the shared
    /// `MathParityCorpus` must agree with `isRenderable` exactly.
    /// `MathPreviewPreprocessorTests` (app target) runs the SAME corpus
    /// through Preview's own path.
    @Test(arguments: MathParityCorpus.cases)
    func isRenderableMatchesTheSharedParityCorpus(_ testCase: MathParityCorpus.Case) {
        let span = MathSpan(range: 0 ..< 1, style: testCase.style, latex: testCase.latex)
        #expect(MathImageRenderer.isRenderable(span) == testCase.isRenderable, "\(testCase.comment)")
    }
}
