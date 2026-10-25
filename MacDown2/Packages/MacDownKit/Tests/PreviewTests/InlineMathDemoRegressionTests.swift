import AppKit
import Foundation
@testable import Preview
import SwiftUI
import Testing
@testable import Textual

@Suite("Inline math after a preview edit")
@MainActor
struct InlineMathDemoRegressionTests {
    private let equationLine = "The area of a circle is $A = \\pi r^2$, and"

    @Test func exactEquationParsesAsOneMathAttachment() throws {
        let parsed = try PreviewMarkupParser(syntaxExtensions: [.math]).attributedString(for: equationLine)
        let attachments = parsed.runs.compactMap(\.textual.attachment)

        #expect(attachments.count == 1)
        #expect(attachments.first?.description == "$A = \\pi r^2$")
        #expect(String(parsed.characters) == "The area of a circle is \u{FFFC}, and")
    }

    /// Reproduced from a real alpha recording: with a stable PreviewBlock ID,
    /// changing prose to this equation left only the superscript and a solid
    /// bar where the rest of the attachment should have been. A fresh view of
    /// the same text drew the entire equation. Keep the host offscreen so this
    /// regression never steals the user's desktop focus.
    @Test func editingAnExistingBlockDoesNotLeaveAStaleMathSymbol() throws {
        let resourceID = UUID()
        let blockID = UUID()
        func preview(_ text: String) -> TextualMarkdownPreview {
            TextualMarkdownPreview(
                document: nil, text: text, theme: .default(for: .light),
                resourceImageLoader: PreviewResourceImageLoader(), resourceLoadID: resourceID,
                blocks: [PreviewBlock(id: blockID, kind: .paragraph, source: text, lineRange: 1 ... 1)]
            )
        }

        let hosting = NSHostingView(rootView: preview("The area of a circle is "))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 140)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        for attempt in 0 ..< 8 {
            hosting.rootView = preview(equationLine)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

            // The stale attachment produced a continuous dark bar over one-sixth
            // of the preview width. Valid glyphs have no such horizontal run.
            var longestRun = 0
            for row in 0 ..< bitmap.pixelsHigh {
                var run = 0
                for column in 0 ..< bitmap.pixelsWide {
                    let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(NSColorSpace.deviceRGB)
                    let isDark = (color?.redComponent ?? 1) < 0.25 &&
                        (color?.greenComponent ?? 1) < 0.25 &&
                        (color?.blueComponent ?? 1) < 0.25
                    run = isDark ? run + 1 : 0
                    longestRun = max(longestRun, run)
                }
            }
            #expect(longestRun < bitmap.pixelsWide / 12, "Stale math attachment after edit \(attempt)")
            hosting.rootView = preview("The area of a circle is ")
            hosting.layoutSubtreeIfNeeded()
        }
    }
}
