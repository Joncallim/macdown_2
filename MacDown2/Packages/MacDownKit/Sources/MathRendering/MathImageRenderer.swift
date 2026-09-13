import AppKit
import CoreGraphics
import Foundation
import Math
import SwiftUI
@_spi(Textual) import SwiftUIMath

/// Renders one `MathSpan` to PNG bytes via `SwiftUIMath`'s `Math` view and
/// SwiftUI's `ImageRenderer` — the same rendering engine Preview's own
/// (currently dormant) `Textual`-driven math display uses, so Preview and
/// Export produce visually consistent equations from one engine
/// (epic-19-implementation.md §1, §17 Slice 2).
///
/// `Math` here — the type from `import SwiftUIMath` — is `SwiftUIMath.Math`,
/// the LaTeX-rendering SwiftUI view; it is unrelated to this package's own
/// `Math` module (`MathSpan`/`MathContribution`), which declares no type
/// named bare `Math` and so cannot collide with it.
@MainActor
public enum MathImageRenderer {
    /// Chosen for legible on-screen/print quality without producing
    /// unreasonably large `data:` URIs (epic-19-implementation.md §11).
    /// `nonisolated`: a plain constant, safe to read from any context
    /// without hopping onto the main actor just to build an
    /// `ExportMathRenderContext` (`MathExportRegistry.swift`, app target).
    public nonisolated static let standardScale: CGFloat = 3

    private static let font = SwiftUIMath.Math.Font(name: .latinModern, size: 18)

    /// Matches the `MathImageRendering` typealias (`Math` target) so this
    /// can be passed directly as `MathContribution`'s injected renderer;
    /// being `@MainActor`-isolated while that typealias is not is fine —
    /// Swift hops onto the main actor when this is called through the
    /// closure value, matching how `ImageRenderer`/AppKit work already
    /// requires main-actor affinity elsewhere in this app (epic-12
    /// §3.7's own "only UI snapshot/save-panel state and WebKit/AppKit/
    /// PDFKit work are main-actor" rule).
    public static func render(span: MathSpan, context: ExportMathRenderContext) throws -> Data {
        let style: SwiftUIMath.Math.TypesettingStyle = span.style == .inline ? .text : .display

        let bounds = SwiftUIMath.Math.typographicBounds(
            for: span.latex, fitting: ProposedViewSize(width: nil, height: nil), font: font, style: style
        )
        guard bounds.size.width > 0, bounds.size.height > 0 else {
            throw MathRenderError.couldNotTypeset
        }

        let color = Color(
            red: context.foregroundRed, green: context.foregroundGreen, blue: context.foregroundBlue
        )
        let view = SwiftUIMath.Math(span.latex)
            .mathFont(font)
            .mathTypesettingStyle(style)
            .foregroundStyle(color)
            .frame(width: bounds.size.width, height: bounds.size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = context.pixelScale

        guard let cgImage = renderer.cgImage else {
            throw MathRenderError.couldNotTypeset
        }
        guard let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw MathRenderError.couldNotTypeset
        }
        return pngData
    }
}
