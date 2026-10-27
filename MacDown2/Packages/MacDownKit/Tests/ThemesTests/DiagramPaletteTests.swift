import Foundation
import Testing
@testable import Themes

@Suite("Neutral diagram palette")
struct DiagramPaletteTests {
    @Test func serializationAndFingerprintAreStable() throws {
        let palette = DiagramPalette.neutralLight
        #expect(palette.fingerprint == (
            "neutral-light-v1|#FFFFFF|#1A1A1A|#1A1A1A|#F3F5F8|#285EA8|#526274|"
                + palette.pieColors.joined(separator: "|")
        ))
        #expect(palette.rendererArguments["canvas"] == "#FFFFFF")
        #expect(palette.rendererArguments["text"] == "#1A1A1A")
        let encoded = try JSONEncoder().encode(palette)
        #expect(try JSONDecoder().decode(DiagramPalette.self, from: encoded) == palette)
        let altered = try #require(String(data: encoded, encoding: .utf8))
            .replacingOccurrences(of: "#FFFFFF", with: "#000000")
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DiagramPalette.self, from: Data(altered.utf8))
        }
    }

    @Test func defaultTextAndAccentStayReadable() {
        let palette = DiagramPalette.neutralLight
        #expect(Self.contrast(palette.text, palette.canvas) >= 7)
        #expect(Self.contrast(palette.text, palette.nodeFill) >= 7)
        #expect(Self.contrast("#FFFFFF", palette.accent) >= 4.5)
    }

    @Test func screenDefaultsResolveTextAndCanvasIndependently() throws {
        let foreground = ThemeColor(red: 0.9, green: 0.8, blue: 0.7)
        let background = ThemeColor(red: 0.1, green: 0.2, blue: 0.3)
        let dark = DiagramPalette.resolved(for: .screen, foreground: foreground, background: background)
        let light = DiagramPalette.resolved(for: .screen, foreground: background, background: foreground)
        #expect(dark.text == "#E6CCB3")
        #expect(dark.stroke == dark.text)
        #expect(dark.canvas == "#1A334D")
        #expect(dark.nodeFill == dark.canvas)
        #expect(dark.fingerprint != light.fingerprint)
        #expect(try JSONDecoder().decode(DiagramPalette.self, from: JSONEncoder().encode(dark)) == dark)
        let printPalette = DiagramPalette.resolved(for: .print, foreground: foreground, background: background)
        #expect(printPalette == .neutralLight)
        #expect(printPalette.text == "#1A1A1A")
        #expect(printPalette.canvas == "#FFFFFF")
    }

    @Test func screenColorsClampFiniteComponentsAndRejectNonFiniteColors() {
        let palette = DiagramPalette.resolved(
            for: .screen,
            foreground: ThemeColor(red: -1, green: 2, blue: 0.5),
            background: ThemeColor(red: .nan, green: .infinity, blue: 0)
        )
        #expect(palette.text == "#00FF80")
        #expect(palette.canvas == "#FFFFFF")
    }

    private static func contrast(_ first: String, _ second: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let digits = Array(hex.dropFirst())
            let channels = stride(from: 0, to: 6, by: 2).map { index -> Double in
                let byte = Int(String(digits[index ... index + 1]), radix: 16) ?? 0
                let value = Double(byte) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}
