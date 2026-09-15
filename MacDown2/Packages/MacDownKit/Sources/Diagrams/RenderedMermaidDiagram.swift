import Foundation

/// The result of a successful render (epic-20-implementation.md §6).
/// Width/height are the diagram's own natural size in points, taken from the
/// SVG's viewBox, so a display view can reserve correctly-proportioned
/// layout space before decoding the image.
public struct RenderedMermaidDiagram: Sendable, Equatable {
    public let svg: String
    public let naturalWidth: Double
    public let naturalHeight: Double

    public init(svg: String, naturalWidth: Double, naturalHeight: Double) {
        self.svg = svg
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
    }
}
