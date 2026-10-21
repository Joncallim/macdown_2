@testable import ExportService
import Foundation
import Testing

@Suite("SVG namespace isolation regressions")
struct SVGIDNamespaceIsolationTests {
    @Test func unresolvedInteractiveFragmentAndARIAIDFailClosed() {
        let html = ##"<svg id="root"><a href="#outside"><text>Go</text></a></svg>"##
        #expect(SVGIDNamespace.rewrite(html, occurrence: 6) == nil)
        #expect(SVGIDNamespace.rewrite(
            #"<svg id="root"><rect aria-describedby="outside"/></svg>"#, occurrence: 6
        ) == nil)
        #expect(SVGIDNamespace.rewrite(
            #"<svg id="root"><style>#outside{fill:red}</style></svg>"#, occurrence: 6
        ) == nil)
    }

    @Test func syntheticRootScopeDoesNotTurnAnUnresolvedPaintIntoARealTarget() throws {
        let html = #"<svg><style>.shape{stroke:red}</style>"#
            + #"<rect class="shape" fill="url(#mtScope)"/></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 7))
        #expect(result.contains(#"id="mt117-svg-7-0-mtScope_""#))
        #expect(result.contains(#"fill="url(#mt117-svg-7-0-mtScope)""#))
        #expect(result.contains(#"#mt117-svg-7-0-mtScope_ .shape{stroke:red}"#))
    }

    @Test func encodedReferenceCannotBecomeTheSyntheticRootID() throws {
        let html = #"<svg><rect fill="url(#mt&#83;cope)"/></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 8))
        #expect(result.contains(#"id="mt117-svg-8-0-mtScope_""#))
        #expect(result.contains(#"fill="url(#mt117-svg-8-0-mtScope)""#))
    }

    @Test func selectorsThatCanEscapeTheSVGOrMissItsRootFailClosed() {
        for selector in ["#root + p", "#root ~ p", ".diagramRoot", "SVG"] {
            let html = #"<svg id="root" class="diagramRoot"><style>"#
                + selector + #"{color:red}</style></svg>"#
            #expect(SVGIDNamespace.rewrite(html, occurrence: 0) == nil, "\(selector)")
        }
    }

    @Test func animationImportanceAndSignedDelayArePreservedOrRejectedSafely() throws {
        let html = #"<svg id="root"><style>@keyframes pulse{to{opacity:1}}"#
            + #"#root{animation:pulse -0.5s linear !important}</style></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 9))
        #expect(result.contains("animation:mt117-svg-9-0-pulse -0.5s linear !important"))
        #expect(SVGIDNamespace.rewrite(
            #"<svg id="root"><style>#root{animation:var(--motion)}</style></svg>"#,
            occurrence: 0
        ) == nil)
    }

    @Test func embeddedFontFamilyCannotAffectAuthoredDocumentStyles() throws {
        let html = #"<svg id="root"><style>@font-face{font-family:"diagramFace";"#
            + #"src:url("data:font/woff;base64,AA==");}"#
            + #"#root text{font-family:"diagramFace"}</style><text>Sample</text></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 3))
        #expect(result.contains(#"font-family:"mt117-svg-3-0-diagramFace""#))
        #expect(!result.contains(#"font-family:"diagramFace""#))
    }

    @Test func fontFacesWithUnsupportedCrossStyleOrInlineReferencesFailClosed() {
        let face = #"<style>@font-face{font-family:diagramFace;"#
            + #"src:url("data:font/woff;base64,AA==")}</style>"#
        for extra in [
            #"<style>#root text{font-family:diagramFace}</style>"#,
            #"<text font-family="diagramFace">A</text>"#,
            #"<text style="font-family:diagramFace">A</text>"#,
        ] {
            #expect(SVGIDNamespace.rewrite(#"<svg id="root">"# + face + extra + "</svg>", occurrence: 0) == nil)
        }
        let local = #"<svg id="root"><style>@font-face{font-family:diagramFace;"#
            + #"src:local("Private Font")}</style></svg>"#
        #expect(SVGIDNamespace.rewrite(local, occurrence: 0) == nil)
    }
}
