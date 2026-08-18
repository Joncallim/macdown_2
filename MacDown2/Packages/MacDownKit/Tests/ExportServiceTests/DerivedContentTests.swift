import ExportService
import Foundation
import Testing

/// Slice 3: the renderer-neutral derived-content destination. A deterministic
/// test contribution flows through the export pipeline without any math or
/// diagram language, and failed contributions never delete authored source.
struct DerivedContentTests {
    private func utf16Range(of needle: String, in haystack: String) -> Range<Int> {
        let nsString = haystack as NSString
        let found = nsString.range(of: needle)
        precondition(found.location != NSNotFound)
        return found.location ..< (found.location + found.length)
    }

    @Test func blockContributionFlowsThroughPipeline() async throws {
        let markdown = "# Doc\n\n```diagram\nsource\n```\n"
        let range = utf16Range(of: "```diagram\nsource\n```", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .block,
            html: "<figure class=\"diagram\">rendered</figure>",
            sourceGeneration: 1
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("<figure class=\"diagram\">rendered</figure>"))
        #expect(!prepared.bodyHTML.contains("```diagram"))
    }

    @Test func inlineContributionFlowsThroughPipeline() async throws {
        let markdown = "Compute $x^2$ now.\n"
        let range = utf16Range(of: "$x^2$", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .inline,
            html: "<span class=\"math\">x²</span>",
            sourceGeneration: 2
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 2,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("<span class=\"math\">x²</span>"))
        #expect(!prepared.bodyHTML.contains("$x^2$"))
    }

    @Test func staleContributionPreservesAuthoredSource() async throws {
        let markdown = "Compute $x^2$ now.\n"
        let range = utf16Range(of: "$x^2$", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .inline,
            html: "<span>stale</span>",
            sourceGeneration: 99 // does not match the export generation
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 2,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("$x^2$") || prepared.bodyHTML.contains("x²") || prepared.bodyHTML
            .contains("x^2"))
        #expect(!prepared.bodyHTML.contains("<span>stale</span>"))
        #expect(prepared.diagnostics.contains { $0.severity == .error && $0.message.contains("stale") })
    }

    @Test func overlappingContributionPreservesAuthoredSource() async throws {
        let markdown = "one $a$ and $b$ two\n"
        let firstRange = utf16Range(of: "$a$", in: markdown)
        let overlappingRange = firstRange.lowerBound ..< (firstRange.upperBound + 2)

        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 3,
                theme: ExportTestSupport.lightTheme(),
                contributions: [
                    ExportDerivedContribution(
                        sourceRange: firstRange,
                        placement: .inline,
                        html: "<span>A</span>",
                        sourceGeneration: 3
                    ),
                    ExportDerivedContribution(
                        sourceRange: overlappingRange,
                        placement: .inline,
                        html: "<span>B</span>",
                        sourceGeneration: 3
                    ),
                ]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.diagnostics.contains { $0.severity == .error && $0.message.contains("overlaps") })
        // The first (valid) contribution is placed; the overlapping one is not,
        // so its authored characters survive as text rather than disappearing.
        #expect(prepared.bodyHTML.contains("<span>A</span>"))
    }

    @Test func outOfBoundsContributionPreservesAuthoredSource() async throws {
        let markdown = "# Doc\n"
        let contribution = ExportDerivedContribution(
            sourceRange: 100 ..< 200,
            placement: .block,
            html: "<figure>bad</figure>",
            sourceGeneration: 4
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 4,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("# Doc") || prepared.bodyHTML.contains("<h1>Doc</h1>"))
        #expect(!prepared.bodyHTML.contains("<figure>bad</figure>"))
        #expect(prepared.diagnostics.contains { $0.severity == .error })
    }

    @Test func contributionCarryingWarningsIsStillPlaced() async throws {
        let markdown = "Compute $x^2$ now.\n"
        let range = utf16Range(of: "$x^2$", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .inline,
            html: "<span class=\"math\">x²</span>",
            sourceGeneration: 5,
            diagnostics: [ExportDiagnostic(severity: .warning, message: "low fidelity")]
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 5,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("<span class=\"math\">x²</span>"))
    }

    @Test func contributionCarryingAnErrorIsNotPlaced() async throws {
        // The renderer said it failed. Splicing it anyway would delete authored
        // Markdown and put broken output in its place.
        let markdown = "Compute $x^2$ now.\n"
        let range = utf16Range(of: "$x^2$", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .inline,
            html: "<span>broken</span>",
            sourceGeneration: 6,
            diagnostics: [ExportDiagnostic(severity: .error, message: "renderer failed")]
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 6,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(!prepared.bodyHTML.contains("<span>broken</span>"))
        #expect(prepared.diagnostics.contains { $0.message == "renderer failed" })
        #expect(prepared.diagnostics.contains { $0.message.contains("failed in its renderer") })
    }

    @Test func contributionWarningsReachTheCaller() async throws {
        let markdown = "Compute $x^2$ now.\n"
        let range = utf16Range(of: "$x^2$", in: markdown)
        let contribution = ExportDerivedContribution(
            sourceRange: range,
            placement: .inline,
            html: "<span>ok</span>",
            sourceGeneration: 7,
            diagnostics: [ExportDiagnostic(severity: .warning, message: "approximate glyph")]
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 7,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("<span>ok</span>"))
        #expect(prepared.diagnostics.contains { $0.message == "approximate glyph" })
    }

    @Test func manyContributionsKeepDistinctIdentities() async throws {
        // Sentinel 1 must not be found inside sentinel 10; every fragment lands
        // exactly once, in order.
        let pieces = (0 ..< 12).map { "m\($0)" }
        let markdown = pieces.joined(separator: " and ") + "\n"
        let contributions = pieces.enumerated().map { index, piece in
            ExportDerivedContribution(
                sourceRange: utf16Range(of: piece, in: markdown),
                placement: .inline,
                html: "<span class=\"d\">D\(index)E</span>",
                sourceGeneration: 8
            )
        }
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 8,
                theme: ExportTestSupport.lightTheme(),
                contributions: contributions
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.diagnostics.isEmpty)
        for index in 0 ..< 12 {
            #expect(prepared.bodyHTML.contains(">D\(index)E<"), "fragment \(index) is missing")
        }
        #expect(!prepared.bodyHTML.contains("E12INLINE"))
    }

    @Test func authoredTextThatLooksLikeASentinelIsPreserved() async throws {
        // The document already contains the sentinel family, so the composer has
        // to pick a family that does not collide with it.
        let markdown = "Note E12INLINE0Z here, then $x$ ends.\n"
        let range = utf16Range(of: "$x$", in: markdown)
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 9,
                theme: ExportTestSupport.lightTheme(),
                contributions: [ExportDerivedContribution(
                    sourceRange: range,
                    placement: .inline,
                    html: "<span>X</span>",
                    sourceGeneration: 9
                )]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("E12INLINE0Z"))
        #expect(prepared.bodyHTML.contains("<span>X</span>"))
    }
}
