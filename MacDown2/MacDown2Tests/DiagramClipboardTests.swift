import AppKit
@testable import MacDown2
import Testing
import UniformTypeIdentifiers

/// Real evidence for issue #86: a genuine `NSPasteboard.general` round trip,
/// not a mock — confirms the diagram's real SVG markup actually lands on
/// the system pasteboard, in both a plain-text form (pastes into any text
/// editor) and a real `public.svg-image` form.
@Suite("DiagramClipboard", .serialized)
struct DiagramClipboardTests {
    @Test func copySVGWritesPlainTextRepresentation() {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"5\"/></svg>"
        DiagramClipboard.copySVG(svg)
        #expect(NSPasteboard.general.string(forType: .string) == svg)
    }

    @Test func copySVGWritesRealSVGImageTypeRepresentation() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\"/></svg>"
        DiagramClipboard.copySVG(svg)
        let svgType = try #require(UTType("public.svg-image"))
        let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(svgType.identifier))
        let roundTripped = try #require(data.flatMap { String(data: $0, encoding: .utf8) })
        #expect(roundTripped == svg)
    }

    @Test func copySVGReplacesAnyPreviousPasteboardContents() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("stale content", forType: .string)
        DiagramClipboard.copySVG("<svg></svg>")
        #expect(NSPasteboard.general.string(forType: .string) == "<svg></svg>")
    }
}
