import ExportService
import Foundation
import Testing
import Themes

/// The renderer recurses once per nesting level; on a cooperative thread's
/// stack a few thousand levels killed the app (signal 10) during export.
struct DeepNestingExportTests {
    private func exportBody(_ text: String) async throws -> String {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: text, sourceGeneration: 1, theme: BundledThemes.light),
            target: .html(url: URL(fileURLWithPath: "/tmp/deep-nesting.html"), mode: .standalone(style: .embedded))
        )
        return prepared.bodyHTML
    }

    @Test func aThirtyThousandDeepBlockQuoteExports() async throws {
        let html = try await exportBody(String(repeating: ">", count: 30000) + " x\n")

        #expect(html.contains("x"))
        #expect(html.contains("<blockquote>"))
    }

    @Test func aFifteenHundredDeepListExports() async throws {
        let text = (0 ..< 1500).map { String(repeating: "  ", count: $0) + "- a\n" }.joined()

        #expect(try await exportBody(text).contains("<li>"))
    }
}
