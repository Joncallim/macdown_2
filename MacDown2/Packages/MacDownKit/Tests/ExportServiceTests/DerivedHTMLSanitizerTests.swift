import ExportService
import Foundation
import Testing

/// Diagram SVG is built from author-controlled text and spliced into exports verbatim, so a
/// `javascript:` link in a Graphviz `URL=` or a D2 `link:` survived into the document.
struct DerivedHTMLSanitizerTests {
    private func exportedBody(placing html: String) async throws -> String {
        let markdown = "```diagram\nsource\n```\n"
        let found = (markdown as NSString).range(of: "```diagram\nsource\n```")
        let contribution = ExportDerivedContribution(
            sourceRange: found.location ..< (found.location + found.length),
            placement: .block,
            html: html,
            sourceGeneration: 1
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/sanitise.html"), mode: .standalone(style: .embedded))
        )
        return prepared.bodyHTML
    }

    @Test(arguments: [
        #"<svg><a xlink:href="javascript:alert(document.domain)"><text>x</text></a></svg>"#,
        #"<svg><a href="javascript:alert(1)"><text>x</text></a></svg>"#,
        #"<svg><a href='  JaVa&#x73;cript:alert(1)'><text>x</text></a></svg>"#,
        #"<svg><a href="java&Tab;script&colon;alert(1)"><text>x</text></a></svg>"#,
        #"<svg><a href=javascript:alert(1)><text>x</text></a></svg>"#,
        #"<svg><a href="data:text/html;base64,PHNjcmlwdD4="><text>x</text></a></svg>"#,
    ])
    func scriptSchemesInLinksAreNeutralised(_ svg: String) async throws {
        let body = try await exportedBody(placing: svg)

        #expect(!body.lowercased().contains("javascript"))
        #expect(!body.lowercased().contains("data:text/html"))
        #expect(body.contains("<text>x</text>"))
    }

    @Test func scriptElementsAndEventHandlersAreRemoved() async throws {
        let body = try await exportedBody(
            placing: #"<svg onload="alert(1)"><script>alert(2)</script><rect onclick='x()' width="1"/></svg>"#
        )

        #expect(!body.contains("<script"))
        #expect(!body.contains("alert"))
        #expect(!body.contains("onload"))
        #expect(!body.contains("onclick"))
        #expect(body.contains(#"<rect"#))
    }

    @Test func ordinaryLinksAndEmbeddedMathImagesSurvive() async throws {
        let html = ##"<a href="https://example.com/a?b=1&amp;c=2">x</a><a href="#n1">y</a>"##
            + #"<img src="data:image/png;base64,AAAA" alt="x^2" width="10" height="10" />"#

        let body = try await exportedBody(placing: html)

        #expect(body.contains(#"href="https://example.com/a?b=1&amp;c=2""#))
        #expect(body.contains(##"href="#n1""##))
        #expect(body.contains(#"src="data:image/png;base64,AAAA""#))
    }
}
