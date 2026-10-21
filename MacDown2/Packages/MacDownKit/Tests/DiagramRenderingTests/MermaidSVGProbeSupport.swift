import AppKit
@testable import DiagramRendering
import Diagrams
import Foundation
import Testing

/// What the harness canvas produced for one SVG input: the normalized SVG
/// it rasterized, the PNG bytes, and the canvas's logical size.
struct MermaidCanvasProbe {
    let svg: String
    let pngData: Data
    let width: Double
    let height: Double
}

/// An SVG `viewBox` (`min-x min-y width height`), kept as raw values so a
/// negative or unusual box is reported exactly as parsed.
struct MermaidSVGViewBox {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}

/// Pixel and SVG inspection helpers shared by `MermaidWebRendererTests`.
enum MermaidSVGProbe {
    @MainActor
    static func canvasProbe(_ svg: String) async throws -> MermaidCanvasProbe {
        let page = try await MermaidHarnessPage.make()
        defer { page.teardown() }
        let result = try await page.inspectSVGCanvasForTesting(svg)
        let renderedSVG = try #require(result["svg"] as? String)
        let pngBase64 = try #require(result["png"] as? String)
        let pngData = try #require(Data(base64Encoded: pngBase64))
        let width = try #require((result["width"] as? NSNumber)?.doubleValue)
        let height = try #require((result["height"] as? NSNumber)?.doubleValue)
        return MermaidCanvasProbe(svg: renderedSVG, pngData: pngData, width: width, height: height)
    }

    static func pngDimensions(_ data: Data) throws -> (width: UInt32, height: UInt32) {
        let bytes = Array(data)
        try #require(bytes.count >= 24)
        let width = bytes[16 ..< 20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let height = bytes[20 ..< 24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return (width, height)
    }

    static func pngPixelEvidence(_ data: Data) throws -> (hasOpaqueWhite: Bool, hasDiagramContent: Bool) {
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var hasOpaqueWhite = false
        var hasDiagramContent = false
        for row in 0 ..< bitmap.pixelsHigh {
            for column in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                let isOpaque = color.alphaComponent >= 0.99
                if isOpaque,
                   color.redComponent >= 0.98,
                   color.greenComponent >= 0.98,
                   color.blueComponent >= 0.98 {
                    hasOpaqueWhite = true
                }
                if color.alphaComponent >= 0.2,
                   color.redComponent < 0.95 || color.greenComponent < 0.95 || color.blueComponent < 0.95 {
                    hasDiagramContent = true
                }
                if hasOpaqueWhite, hasDiagramContent {
                    return (true, true)
                }
            }
        }
        return (hasOpaqueWhite, hasDiagramContent)
    }

    static func svgTag(
        named name: String,
        withClass className: String,
        in svg: String
    ) throws -> String {
        let regex = try NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive])
        let range = NSRange(svg.startIndex..., in: svg)
        for match in regex.matches(in: svg, range: range) {
            guard let matchRange = Range(match.range, in: svg) else { continue }
            let tag = String(svg[matchRange])
            if tag.contains("class=\"\(className)\"") {
                return tag
            }
        }
        throw MermaidRenderError.rendererUnavailable
    }

    static func svgNumberAttribute(_ name: String, from tag: String) throws -> Double {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))=\"([-+0-9.eE]+)\""
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(tag.startIndex..., in: tag)
        let match = try #require(regex.firstMatch(in: tag, range: range))
        let valueRange = try #require(Range(match.range(at: 1), in: tag))
        return try #require(Double(tag[valueRange]))
    }

    static func svgViewBox(in svg: String) throws -> MermaidSVGViewBox {
        let svgTag = try #require(svg.range(of: "<svg\\b[^>]*>", options: [.regularExpression]))
        let tag = String(svg[svgTag])
        let regex = try NSRegularExpression(pattern: "\\bviewBox=\"([^\"]+)\"")
        let range = NSRange(tag.startIndex..., in: tag)
        let match = try #require(regex.firstMatch(in: tag, range: range))
        let valueRange = try #require(Range(match.range(at: 1), in: tag))
        let values = tag[valueRange].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap(Double.init)
        guard values.count == 4 else { throw MermaidRenderError.rendererUnavailable }
        return MermaidSVGViewBox(minX: values[0], minY: values[1], width: values[2], height: values[3])
    }

    static func containsDarkPixel(
        in pngData: Data,
        aroundSVGPoint point: CGPoint,
        viewBox: MermaidSVGViewBox,
        radius: Int
    ) throws -> Bool {
        let bitmap = try #require(NSBitmapImageRep(data: pngData))
        let pixelX = Int(((Double(point.x) - viewBox.minX) / viewBox.width) * Double(bitmap.pixelsWide - 1))
        let pixelY = Int(((Double(point.y) - viewBox.minY) / viewBox.height) * Double(bitmap.pixelsHigh - 1))
        let columns = max(0, pixelX - radius) ... min(bitmap.pixelsWide - 1, pixelX + radius)
        let rows = max(0, pixelY - radius) ... min(bitmap.pixelsHigh - 1, pixelY + radius)
        for row in rows {
            for column in columns {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent >= 0.5,
                   color.redComponent < 0.35,
                   color.greenComponent < 0.35,
                   color.blueComponent < 0.35 {
                    return true
                }
            }
        }
        return false
    }
}
