@testable import DiagramsGraphviz
import Foundation
@testable import GraphvizRendering
import Testing

/// Real, end-to-end pipeline tests — genuine WebKit, genuine bundled
/// viz-js/Graphviz, no fakes.
@Suite("GraphvizWebRenderer")
struct GraphvizWebRendererTests {
    private static let context = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> GraphvizFence {
        GraphvizFence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = GraphvizWebRenderer()
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; b -> c; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        // Confirmed by a real Slice 0 spike: Graphviz's native output has
        // no <foreignObject>, which is exactly why RenderedGraphvizDiagram
        // carries no pngData field — this assertion keeps that assumption
        // honest.
        #expect(!diagram.svg.contains("foreignObject"))
        await renderer.shutdown()
    }

    @Test func renderAppliesThemeColorsToGraphvizDefaults() async throws {
        let renderer = GraphvizWebRenderer()
        let themedContext = GraphvizRenderContext(
            foregroundRed: 0x11 / 255.0, foregroundGreen: 0x22 / 255.0, foregroundBlue: 0x33 / 255.0,
            backgroundRed: 0xEE / 255.0, backgroundGreen: 0xDD / 255.0, backgroundBlue: 0xCC / 255.0
        )
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: themedContext)
        #expect(diagram.svg.localizedCaseInsensitiveContains("#112233"))
        #expect(diagram.svg.localizedCaseInsensitiveContains("#EEDDCC"))
        await renderer.shutdown()
    }

    @Test func sourceLevelGraphvizColorsRemainAuthoritative() async throws {
        let renderer = GraphvizWebRenderer()
        let source = "digraph { node [color=\"#ABCDEF\"]; a -> b; }"
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.range(of: ##"<(ellipse|polygon)[^>]*stroke="#ABCDEF"[^>]*>"##, options: [.regularExpression, .caseInsensitive]) != nil)
        await renderer.shutdown()
    }

    @Test func filledNodesUseAContrastingDefaultFill() async throws {
        let renderer = GraphvizWebRenderer()
        let light = try await renderer.render(
            Self.fence("digraph { node [style=filled]; a -> b; }"),
            context: Self.context
        )
        let dark = try await renderer.render(
            Self.fence("digraph { node [style=filled]; a -> b; }"),
            context: GraphvizRenderContext(
                foregroundRed: 0xEE / 255.0, foregroundGreen: 0xDD / 255.0, foregroundBlue: 0xCC / 255.0,
                backgroundRed: 0x11 / 255.0, backgroundGreen: 0x22 / 255.0, backgroundBlue: 0x33 / 255.0
            )
        )
        #expect(light.svg.localizedCaseInsensitiveContains("fill=\"#FFFFFF\""))
        #expect(light.svg.localizedCaseInsensitiveContains("fill=\"#000000\""))
        #expect(dark.svg.localizedCaseInsensitiveContains("fill=\"#112233\""))
        #expect(dark.svg.localizedCaseInsensitiveContains("fill=\"#EEDDCC\""))
        let authored = try await renderer.render(
            Self.fence("digraph { node [style=filled, fillcolor=\"#ABCDEF\"]; a -> b; }"),
            context: Self.context
        )
        #expect(authored.svg.localizedCaseInsensitiveContains("fill=\"#ABCDEF\""))
        await renderer.shutdown()
    }

    @Test func graphAndClusterDefaultsUseThemeForeground() async throws {
        let renderer = GraphvizWebRenderer()
        let themedContext = GraphvizRenderContext(
            foregroundRed: 0x11 / 255.0, foregroundGreen: 0x22 / 255.0, foregroundBlue: 0x33 / 255.0,
            backgroundRed: 0xEE / 255.0, backgroundGreen: 0xDD / 255.0, backgroundBlue: 0xCC / 255.0
        )
        let source = "digraph { label=\"Graph label\"; subgraph cluster_one { label=\"Cluster label\"; a -> b; } }"
        let diagram = try await renderer.render(Self.fence(source), context: themedContext)
        #expect(diagram.svg.range(of: ##"<polygon[^>]*stroke="#112233"[^>]*>"##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<text[^>]*fill="#112233"[^>]*>Graph label</text>"##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<text[^>]*fill="#112233"[^>]*>Cluster label</text>"##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<polygon[^>]*fill="[^"]+"[^>]*>"##, options: [.regularExpression, .caseInsensitive]) != nil)
        await renderer.shutdown()
    }

    @Test func samePooledPageTracksLightDarkLightContexts() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        let light = Self.context
        let dark = GraphvizRenderContext(
            foregroundRed: 0xEE / 255.0, foregroundGreen: 0xDD / 255.0, foregroundBlue: 0xCC / 255.0,
            backgroundRed: 0x11 / 255.0, backgroundGreen: 0x22 / 255.0, backgroundBlue: 0x33 / 255.0
        )
        let lightSVG = try await renderer.render(Self.fence("digraph { a -> b; }"), context: light).svg
        let darkSVG = try await renderer.render(Self.fence("digraph { a -> b; }"), context: dark).svg
        let lightAgainSVG = try await renderer.render(Self.fence("digraph { a -> b; }"), context: light).svg
        #expect(lightSVG.localizedCaseInsensitiveContains("#000000"))
        #expect(lightSVG.localizedCaseInsensitiveContains("#ffffff"))
        #expect(darkSVG.localizedCaseInsensitiveContains("#eeddcc"))
        #expect(darkSVG.localizedCaseInsensitiveContains("#112233"))
        #expect(lightAgainSVG.localizedCaseInsensitiveContains("#000000"))
        #expect(lightAgainSVG.localizedCaseInsensitiveContains("#ffffff"))
        await renderer.shutdown()
    }

    @Test func nonFiniteAndOutOfRangeComponentsNormalizeSafely() async throws {
        let renderer = GraphvizWebRenderer()
        let context = GraphvizRenderContext(
            foregroundRed: .nan, foregroundGreen: .infinity, foregroundBlue: -.infinity,
            backgroundRed: 2, backgroundGreen: -1, backgroundBlue: .nan
        )
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: context)
        #expect(diagram.svg.localizedCaseInsensitiveContains("#000000"))
        #expect(diagram.svg.range(of: #"(#[fF][fF]0000|\bred\b)"#, options: .regularExpression) != nil)
        #expect(!diagram.svg.localizedCaseInsensitiveContains("nan"))
        #expect(!diagram.svg.localizedCaseInsensitiveContains("infinity"))
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = GraphvizWebRenderer()
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> "), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> "), context: Self.context)
        }
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = GraphvizWebRenderer(timeout: .milliseconds(1))
        await #expect(throws: GraphvizRenderError.timedOut) {
            _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = GraphvizWebRenderer(maxOutputBytes: 10)
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedGraphvizDiagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(
                        Self.fence("digraph { a\(index) -> b\(index); }"), context: Self.context
                    )
                }
            }
            var count = 0
            for try await diagram in group {
                #expect(diagram.svg.contains("<svg"))
                count += 1
            }
            #expect(count == 6)
        }
        await renderer.shutdown()
    }

    @Test func rendererReinitializesLazilyAfterShutdown() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        await renderer.shutdown()
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    /// Adversarial corpus (epic-21-implementation.md Slice 5, mirroring
    /// epic-20-implementation.md §15): a genuinely larger, more realistic
    /// diagram — not just a two-node smoke test — to catch problems that
    /// only appear with real layout complexity. 12 nodes, a cluster, and
    /// mixed node/edge styling.
    @Test func renderHandlesAModeratelyComplexDiagramWithinTheDefaultTimeout() async throws {
        let renderer = GraphvizWebRenderer()
        let source = """
        digraph Pipeline {
            rankdir=LR;
            node [shape=box];
            Start [shape=ellipse];
            End [shape=ellipse];
            subgraph cluster_ingest {
                label = "Ingest";
                Fetch; Parse; Validate;
                Fetch -> Parse -> Validate;
            }
            subgraph cluster_process {
                label = "Process";
                Transform; Enrich; Aggregate;
                Transform -> Enrich -> Aggregate;
            }
            Start -> Fetch;
            Validate -> Transform [style=dashed];
            Aggregate -> Store [color=blue];
            Store [shape=cylinder];
            Store -> End;
            Validate -> Error [color=red];
            Error -> End [color=red];
        }
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        await renderer.shutdown()
    }

    /// Adversarial corpus: whitespace-only source is not valid DOT syntax
    /// (a DOT file requires a `graph`/`digraph` keyword) and must fail the
    /// same safe, diagnosable way as any other malformed input — never
    /// hang, never crash, never produce an empty but "successful" diagram.
    @Test func renderFailsSafelyOnWhitespaceOnlySource() async throws {
        let renderer = GraphvizWebRenderer()
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("   \n\n   "), context: Self.context)
        }
        await renderer.shutdown()
    }
}
