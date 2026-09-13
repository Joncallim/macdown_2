import Foundation

/// One rendered equation: PNG bytes plus the LOGICAL (unscaled, point-space)
/// size the image should occupy when displayed — as opposed to its pixel
/// dimensions, which are `logicalWidth/logicalHeight * ExportMathRenderContext
/// .pixelScale` for retina-quality output.
///
/// Adversarial-review finding (post-merge, `chatgpt-codex-connector`):
/// `MathContribution.imgTag` originally embedded only the PNG bytes with no
/// `width`/`height`, so a browser/WKWebView had no DPI hint and rendered
/// every equation at its native PIXEL size — `pixelScale`× too large (3×
/// with the standard scale). `imgTag` now emits `width`/`height` from this
/// type's logical size, the same "declare the logical size, let pixel
/// density scale the bitmap" pattern any ordinary retina `<img>` uses.
public struct RenderedMathImage: Sendable {
    public let pngData: Data
    public let logicalWidth: Double
    public let logicalHeight: Double

    public init(pngData: Data, logicalWidth: Double, logicalHeight: Double) {
        self.pngData = pngData
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
    }
}
