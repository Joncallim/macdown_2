import Contributions
import Foundation
import MarkdownEngine
@testable import Math
import Testing

@Suite("MathContribution")
struct MathContributionTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1, pixelScale: 3
    )

    private static func document() -> MarkdownDocument {
        MarkdownDocument(
            body: "", bodyLineOffset: 0, blocks: [], headings: [], frontMatter: nil,
            sourceMap: SourceMap(text: ""), revision: 0, options: .default
        )
    }

    @Test func runReturnsNothingWhenSourceHasNoMath() async throws {
        let contribution = MathContribution(context: Self.context) { _, _ in Data() }
        let results = try await contribution.run(
            document: Self.document(),
            sourceText: "no math here",
            sourceGeneration: 0
        )
        #expect(results.isEmpty)
    }

    @Test func runProducesOneHTMLResultPerSpanWithCorrectPlacement() async throws {
        let contribution = MathContribution(context: Self.context) { span, _ in
            Data("PNG:\(span.latex)".utf8)
        }
        let results = try await contribution.run(
            document: Self.document(), sourceText: "Inline $a=1$ and $$b=2$$ display.", sourceGeneration: 7
        )

        #expect(results.count == 2)

        let inline = results[0]
        #expect(inline.contributionID == "math")
        #expect(inline.sourceGeneration == 7)
        #expect(inline.diagnostics.isEmpty)
        guard case let .html(inlineHTML) = inline.content?.representation else {
            Issue.record("expected .html representation")
            return
        }
        #expect(inline.content?.placement == .inline)
        #expect(inlineHTML.contains("data:image/png;base64,"))
        #expect(inlineHTML.contains("alt=\"a=1\""))

        let display = results[1]
        #expect(display.content?.placement == .block)
        guard case let .html(displayHTML) = display.content?.representation else {
            Issue.record("expected .html representation")
            return
        }
        #expect(displayHTML.contains("alt=\"b=2\""))
    }

    /// Fault isolation (epic-19-implementation.md §4 invariant 2, §9): one
    /// span's renderer failure does not prevent another span's success, and
    /// is reported as its own diagnostic-bearing, content-less result.
    @Test func runIsolatesOneFailingSpanFromASucceedingSibling() async throws {
        let contribution = MathContribution(context: Self.context) { span, _ in
            if span.latex == "bad" {
                throw MathRenderError.couldNotTypeset
            }
            return Data("PNG:\(span.latex)".utf8)
        }
        let results = try await contribution.run(
            document: Self.document(), sourceText: "$bad$ then $good$", sourceGeneration: 0
        )

        #expect(results.count == 2)
        #expect(results[0].content == nil)
        #expect(results[0].diagnostics.count == 1)
        #expect(results[0].diagnostics.first?.severity == .error)
        #expect(results[1].content != nil)
        #expect(results[1].diagnostics.isEmpty)
    }

    /// If the injected renderer itself throws `CancellationError` (as
    /// opposed to the ambient task being cancelled, covered below), that
    /// must propagate rather than being caught and turned into an isolated
    /// per-span diagnostic like any other renderer failure.
    @Test func runPropagatesARendererThrownCancellationErrorRatherThanIsolatingIt() async throws {
        actor Attempts {
            var seen: [String] = []
            func record(_ latex: String) {
                seen.append(latex)
            }
        }
        let attempts = Attempts()
        let contribution = MathContribution(context: Self.context) { span, _ in
            await attempts.record(span.latex)
            if span.latex == "second" {
                throw CancellationError()
            }
            return Data()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await contribution.run(
                document: Self.document(), sourceText: "$first$ $second$ $third$", sourceGeneration: 0
            )
        }
        #expect(await attempts.seen == ["first", "second"])
    }

    /// Mirrors `ContributionRegistryTests.cancellationPropagatesOutOfTheRegistryRun`
    /// (epic-14-implementation.md §6.1, §8): cancelling the ambient task
    /// stops `run` via its own `Task.checkCancellation()` before the NEXT
    /// span's renderer call. This proves cross-span cancellation, not
    /// mid-render cancellation — the injected renderer here uses a
    /// cooperative `Task.sleep`, unlike the real, production
    /// `MathImageRenderer.render`, which is synchronous, `@MainActor`, and
    /// CPU-bound (SwiftUI `ImageRenderer` layout + PNG encoding) with no
    /// internal cancellation checks of its own — a single equation's
    /// render, once started, always runs to completion (adversarial-review
    /// finding). This is an accepted, bounded limitation, not a defect:
    /// one equation's layout is a small, fast, non-pathological unit of
    /// work, the same way epic-12 §3.7 accepts that "a single C parse/
    /// render cannot necessarily be interrupted mid-call."
    @Test func runStopsBetweenSpansWhenTheAmbientTaskIsCancelled() async {
        let contribution = MathContribution(context: Self.context) { _, _ in
            try await Task.sleep(for: .seconds(3600))
            return Data()
        }

        let task = Task {
            try await contribution.run(
                document: Self.document(), sourceText: "$only$", sourceGeneration: 0
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation to propagate as an error")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }

    /// Adversarial-review finding (epic-19-implementation.md §18):
    /// `MathSpanScanner` has no block-structure awareness on its own, so
    /// `run` must exclude spans inside a code block itself — a real parse
    /// (not the hand-built empty fixture the other tests use) is required
    /// here since the exclusion check reads `document.blocks`.
    @Test func runExcludesASpanInsideAFencedCodeBlock() async throws {
        let text = "Real math: $x=1$.\n\n```\nprice is $5, $10\n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let contribution = MathContribution(context: Self.context) { span, _ in Data("PNG:\(span.latex)".utf8) }

        let results = try await contribution.run(document: parsed, sourceText: text, sourceGeneration: 0)

        #expect(results.count == 1)
        guard case let .html(html) = results.first?.content?.representation else {
            Issue.record("expected .html representation")
            return
        }
        #expect(html.contains("alt=\"x=1\""))
    }

    @Test func runExcludesEveryMathLikeSpanInsideAFencedCodeBlockEvenWhenNoOtherMathExists() async throws {
        let text = "```\n$5, $10\n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let contribution = MathContribution(context: Self.context) { _, _ in Data() }

        let results = try await contribution.run(document: parsed, sourceText: text, sourceGeneration: 0)

        #expect(results.isEmpty)
    }

    @Test func excludedRangesCoversOnlyCodeAndHTMLBlocks() async throws {
        let text = "Prose.\n\n```\ncode\n```\n\n<div>html</div>\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        #expect(MathContribution.excludedRanges(in: parsed).count == 2)
    }

    @Test func imgTagEscapesHTMLSignificantCharactersInAlt() {
        let tag = MathContribution.imgTag(pngData: Data([0x01]), alt: "a < b & \"c\"")
        #expect(tag.contains("alt=\"a &lt; b &amp; &quot;c&quot;\""))
        #expect(!tag.contains("< b"))
    }

    @Test func imgTagEmbedsBase64EncodedPNGData() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let tag = MathContribution.imgTag(pngData: data, alt: "x")
        #expect(tag.contains("data:image/png;base64,\(data.base64EncodedString())"))
    }
}
