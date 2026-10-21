@testable import ExportService
import Foundation
import Testing

@Suite("Per-occurrence SVG identifiers")
struct SVGIDNamespaceTests {
    @Test func repeatedCachedArtworkKeepsItsReferencesWithinEachOccurrence() throws {
        let canonical = ##"<svg id="graph0"><defs><linearGradient id="paint" /></defs>"##
            + ##"<style>#graph0 .node {fill:url(#paint)}</style>"##
            + ##"<g class="node" aria-labelledby="label"><text id="label">A</text>"##
            + ##"<use href="#paint" xlink:href="#label" fill="url(#paint)" /></g></svg>"##
        let first = try #require(SVGIDNamespace.rewrite(canonical, occurrence: 0))
        let second = try #require(SVGIDNamespace.rewrite(canonical, occurrence: 1))
        #expect(first.contains(#"id="mt117-svg-0-0-graph0""#))
        #expect(first.contains(#"id="mt117-svg-0-0-paint""#))
        #expect(first.contains(#"#mt117-svg-0-0-graph0 .node {fill:url(#mt117-svg-0-0-paint)"#))
        #expect(first.contains(#"aria-labelledby="mt117-svg-0-0-label""#))
        #expect(first.contains(##"href="#mt117-svg-0-0-paint""##))
        #expect(first.contains(##"xlink:href="#mt117-svg-0-0-label""##))
        #expect(second.contains(#"id="mt117-svg-1-0-graph0""#))
        #expect(!second.contains("mt117-svg-0-0-"))
        #expect(canonical.contains(#"id="graph0""#))
        #expect(SVGIDNamespace.rewrite(canonical, occurrence: 0) == first)
    }

    @Test func separateSVGsWithinOneContributionDoNotShareAnID() throws {
        let html = #"<div><svg id="same"></svg><svg id="same"></svg></div>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 2))
        #expect(result.contains(#"id="mt117-svg-2-0-same""#))
        #expect(result.contains(#"id="mt117-svg-2-1-same""#))
    }

    @Test func onlyPaintReferencesAreChanged() throws {
        let html = #"<svg><g id="paint" aria-label="url(#paint)" fill="url( '#paint' )""#
            + #" style="stroke:url(#paint)"/></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 0))
        #expect(result.contains(#"aria-label="url(#paint)""#))
        #expect(result.contains(#"fill="url( &#39;#mt117-svg-0-0-paint&#39; )""#))
        #expect(result.contains(#"style="stroke:url(#mt117-svg-0-0-paint)""#))
    }

    @Test func encodedAttributeReferencesResolveToTheirDecodedSVGID() throws {
        let html = #"<svg><g id="node&#49"/><use href="&#35;node1" fill="url(&#35;node1)""#
            + #" aria-labelledby="node&#49;&#9;other"/></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 3))
        #expect(result.contains(#"id="mt117-svg-3-0-node1""#))
        #expect(result.contains(##"href="#mt117-svg-3-0-node1""##))
        #expect(result.contains(#"fill="url(#mt117-svg-3-0-node1)""#))
        #expect(result.contains(#"aria-labelledby="mt117-svg-3-0-node1 other""#))
    }

    @Test func ambiguousOrUnsupportedArtworkPreservesTheAuthoredSource() {
        #expect(SVGIDNamespace.rewrite(#"<svg><g id="x"/><g id="x"/></svg>"#, occurrence: 0) == nil)
        #expect(SVGIDNamespace.rewrite(#"<svg><style>@media screen {#x{fill:red}}</style><g id="x"/></svg>"#,
                                       occurrence: 0) == nil)
        #expect(SVGIDNamespace.rewrite(#"<svg><g id="x"/>"#, occurrence: 0) == nil)
    }

    @Test func rejectedOptInSVGPreservesTheFenceAndOrdinaryExportIsUnchanged() {
        let source = "```diagram\nsource\n```\n"
        let html = #"<svg><style>@media screen {#x{fill:red}}</style><g id="x"/></svg>"#
        let contribution = ExportDerivedContribution(
            sourceRange: 0 ..< source.utf16.count,
            placement: .block, html: html, sourceGeneration: 1
        )
        let optIn = DerivedContentComposer.compose(
            bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
            contributions: [contribution], sourceGeneration: 1, namespaceSVGIDs: true
        )
        #expect(optIn.splicedBody == source)
        #expect(optIn.customNodes.isEmpty)
        #expect(optIn.diagnostics.contains { $0.severity == .error })
        let ordinary = DerivedContentComposer.compose(
            bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
            contributions: [contribution], sourceGeneration: 1
        )
        #expect(ordinary.customNodes.count == 1)
    }
}
