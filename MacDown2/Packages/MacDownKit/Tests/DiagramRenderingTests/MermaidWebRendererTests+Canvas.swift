import AppKit
@testable import DiagramRendering
import Diagrams
import Foundation
import Testing

/// Canvas rasterization and pie-palette cases of the `MermaidWebRenderer`
/// suite, kept in an extension so the suite stays one Swift Testing suite.
extension MermaidWebRendererTests {
    @Test @MainActor func canvasUsesNegativeOriginAndCommaSeparatedExponentViewBoxForPNG() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10,-20,3.2e2,1.8e2">"#
                + #"<circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="-10" y="-20" width="320" height="180" fill="#FFFFFF""##))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsMissing() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="320" height="180" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsInvalid() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 -320 180" width="240" height="135">"#
                + #"<circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 240)
        #expect(probe.height == 135)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="240" height="135" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 480)
        #expect(png.height == 270)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test func pieChartsUseDistinctCategoricalSliceColors() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        pie title Categories
            "One" : 1
            "Two" : 2
            "Three" : 3
            "Four" : 4
            "Five" : 5
            "Six" : 6
            "Seven" : 7
            "Eight" : 8
            "Nine" : 9
            "Ten" : 10
            "Eleven" : 11
            "Twelve" : 12
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        let sliceColors = [
            "#4E79A7", "#F28E2B", "#59A14F", "#E15759", "#B07AA1", "#76B7B2",
            "#EDC949", "#FF9DA7", "#9C755F", "#BAB0AC", "#86BCB6", "#D37295",
        ]
        for color in sliceColors {
            #expect(diagram.svg.range(
                of: ##"<path[^>]*fill="\##(color)"[^>]*class="pieCircle""##,
                options: [.regularExpression, .caseInsensitive]
            ) != nil, "no pie slice filled \(color)")
        }
        let sliceCount = diagram.svg.components(separatedBy: "class=\"pieCircle\"").count - 1
        let legendSwatchCount = diagram.svg.components(separatedBy: "class=\"legend\"").count - 1
        #expect(sliceCount == 12)
        #expect(legendSwatchCount >= 12)
        for legendFill in ["78, 121, 167", "242, 142, 43", "89, 161, 79"] {
            #expect(diagram.svg.range(
                of: ##"<g class="legend"[^>]*>.*fill: rgb\(\##(legendFill)\)"##,
                options: [.regularExpression, .caseInsensitive]
            ) != nil, "no legend swatch filled rgb(\(legendFill))")
        }
        await renderer.shutdown()
    }
}
