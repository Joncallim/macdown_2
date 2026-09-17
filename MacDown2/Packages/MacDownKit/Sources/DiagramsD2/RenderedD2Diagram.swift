import Foundation

/// The result of a successful render (epic-21-implementation.md §3.2,
/// Slice 0 as-built note). Unlike `RenderedMermaidDiagram`, there is no
/// `pngData` field: a real spike confirmed D2's native SVG output (no
/// `<foreignObject>`) displays correctly via AppKit's own `NSImage`
/// decoder, so the same `svg` used for Export also serves native,
/// genuinely resolution-independent on-screen Preview display — no
/// raster-snapshot fallback needed.
public struct RenderedD2Diagram: Sendable, Equatable {
    public let svg: String
    public let naturalWidth: Double
    public let naturalHeight: Double

    public init(svg: String, naturalWidth: Double, naturalHeight: Double) {
        self.svg = svg
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
    }
}
