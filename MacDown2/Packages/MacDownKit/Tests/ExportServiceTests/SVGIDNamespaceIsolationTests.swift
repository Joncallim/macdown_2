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

    @Test func syntheticRootScopeDoesNotTurnAnUnresolvedPaintIntoARealTarget() {
        let html = #"<svg><style>.shape{stroke:red}</style>"#
            + #"<rect class="shape" fill="url(#mtScope)"/></svg>"#
        #expect(SVGIDNamespace.rewrite(html, occurrence: 7) == nil)
    }

    @Test func encodedReferenceCannotBecomeTheSyntheticRootID() {
        let html = #"<svg><rect fill="url(#mt&#83;cope)"/></svg>"#
        #expect(SVGIDNamespace.rewrite(html, occurrence: 8) == nil)
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
            + #"#root{animation:pulse 1s -0.5s linear !important}</style></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 9))
        #expect(result.contains("animation:mt117-svg-9-0-pulse 1s -0.5s linear !important"))
        let leadingDot = #"<svg id="root"><style>@keyframes pulse{to{opacity:1}}"#
            + #"#root{animation:pulse 1s -.5s linear}</style></svg>"#
        let leadingDotResult = try #require(SVGIDNamespace.rewrite(leadingDot, occurrence: 9))
        #expect(leadingDotResult.contains("animation:mt117-svg-9-0-pulse 1s -.5s linear"))
        #expect(SVGIDNamespace.rewrite(
            #"<svg id="root"><style>#root{animation:var(--motion)}</style></svg>"#,
            occurrence: 0
        ) == nil)
        #expect(SVGIDNamespace.rewrite(
            #"<svg id="root"><style>#root{animation:pulse 1s calc(-.5s)}</style></svg>"#,
            occurrence: 0
        ) == nil)
    }

    @Test func embeddedFontFamilyCannotAffectAuthoredDocumentStyles() throws {
        let html = #"<svg id="root"><style>@font-face{font-family:"diagramFace";"#
            + #"src:url("data:font/woff;base64,AA==");}"#
            + #"#root text{font-family:"diagramFace"}</style><text>Sample</text></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 3))
        #expect(result.contains(#"font-family:"mt117-svg-3-0-diagramface""#))
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

    @Test func fontFamilyNamesAreResolvedCaseInsensitively() throws {
        let html = #"<svg id="root"><style>@font-face{font-family:Demo;"#
            + #"src:url("data:font/woff;base64,AA==")}#root text{font-family:demo}</style>"#
            + #"<text>Sample</text></svg>"#
        let result = try #require(SVGIDNamespace.rewrite(html, occurrence: 4))
        #expect(result.contains("font-family:mt117-svg-4-0-demo"))
        #expect(!result.contains("font-family:Demo"))
        #expect(!result.contains("font-family:demo"))
    }

    @Test func reservedEmbeddedFontNamesCannotCaptureGenericOrCSSKeywords() {
        for name in ["serif", "inherit", "initial", "system-ui"] {
            let html = #"<svg id="root"><style>@font-face{font-family:"\#(name)";"#
                + #"src:url("data:font/woff;base64,AA==")}#root text{font-family:\#(name)}</style>"#
                + "<text>Sample</text></svg>"
            #expect(SVGIDNamespace.rewrite(html, occurrence: 0) == nil, "\(name)")
        }
        let fallbackList = #"<svg id="root"><style>@font-face{font-family:Demo;"#
            + #"src:url("data:font/woff;base64,AA==")}#root text{font-family:Demo,sans-serif}</style>"#
            + "<text>Sample</text></svg>"
        #expect(SVGIDNamespace.rewrite(fallbackList, occurrence: 0) == nil)
    }

    @Test func aStyleCannotBorrowAnotherStyleBlocksFontFace() {
        let first = #"<style>@font-face{font-family:A;src:url("data:font/woff;base64,AA==")}"#
            + #"#root text{font-family:B}</style>"#
        let second = #"<style>@font-face{font-family:B;src:url("data:font/woff;base64,AA==")}"#
            + #"#root rect{font-family:B}</style>"#
        let html = #"<svg id="root">"# + first + second + "<text>A</text><rect/></svg>"
        #expect(SVGIDNamespace.rewrite(html, occurrence: 0) == nil)
    }

    @Test func animationNamesNeedAnOwnedKeyframeInTheirStyle() {
        for declaration in ["animation-name:outside", "animation:outside 1s linear"] {
            let html = #"<svg id="root"><style>#root rect{"# + declaration + #"}</style><rect/></svg>"#
            #expect(SVGIDNamespace.rewrite(html, occurrence: 0) == nil)
        }
    }
}
