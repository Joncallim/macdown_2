import AppKit
@testable import DiagramRendering
import Diagrams
import Foundation
import Testing

@Suite("MermaidWebRenderer")
struct MermaidWebRendererTests {
    private static let context = MermaidRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> MermaidFence {
        MermaidFence(source: source, sourceRange: 0 ..< source.count)
    }

    @MainActor
    private static func canvasProbe(
        _ svg: String
    ) async throws -> (svg: String, pngData: Data, width: Double, height: Double) {
        let page = try await MermaidHarnessPage.make()
        defer { page.teardown() }
        let result = try await page.inspectSVGCanvasForTesting(svg)
        let renderedSVG = try #require(result["svg"] as? String)
        let pngBase64 = try #require(result["png"] as? String)
        let pngData = try #require(Data(base64Encoded: pngBase64))
        let width = try #require((result["width"] as? NSNumber)?.doubleValue)
        let height = try #require((result["height"] as? NSNumber)?.doubleValue)
        return (renderedSVG, pngData, width, height)
    }

    private static func pngDimensions(_ data: Data) throws -> (width: UInt32, height: UInt32) {
        let bytes = Array(data)
        try #require(bytes.count >= 24)
        let width = bytes[16 ..< 20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let height = bytes[20 ..< 24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return (width, height)
    }

    private static func pngPixelEvidence(_ data: Data) throws -> (hasOpaqueWhite: Bool, hasDiagramContent: Bool) {
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var hasOpaqueWhite = false
        var hasDiagramContent = false
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let isOpaque = color.alphaComponent >= 0.99
                if isOpaque,
                   color.redComponent >= 0.98,
                   color.greenComponent >= 0.98,
                   color.blueComponent >= 0.98 {
                    hasOpaqueWhite = true
                }
                if color.alphaComponent >= 0.2,
                   color.redComponent < 0.95 || color.greenComponent < 0.95 || color.blueComponent < 0.95 {
                    hasDiagramContent = true
                }
                if hasOpaqueWhite, hasDiagramContent { return (true, true) }
            }
        }
        return (hasOpaqueWhite, hasDiagramContent)
    }

    /// A real, end-to-end pipeline test — genuine WebKit, genuine bundled
    /// Mermaid, no fakes — matching this codebase's precedent
    /// (`MathImageRendererTests`' real `ImageRenderer`,
    /// `DocumentFileMonitorLiveWatcherTests`' real kqueue watcher) of
    /// preferring real dependencies over mocks wherever the real thing can
    /// run under `swift test` (confirmed feasible by this epic's own Slice
    /// 0 spike).
    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = MermaidWebRenderer()
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.svg.range(of: ##"<rect x=\"0\" y=\"0\" width=\"[0-9.]+\" height=\"[0-9.]+\" fill=\"#FFFFFF\""##, options: [.regularExpression]) != nil)
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        await renderer.shutdown()
    }

    /// A real, WebKit-rendered raster snapshot of the diagram, used for
    /// native Preview display (§7.2's `MermaidDiagramBlockView`) because a
    /// real spike proved AppKit's own SVG decoder cannot reliably display
    /// Mermaid's actual output (`RenderedMermaidDiagram`'s own doc comment;
    /// `render.js`'s `png` field comment has the full finding). The PNG
    /// magic-byte check confirms this is genuine decodable image data, not
    /// merely a non-empty byte blob.
    @Test func renderProducesAValidPNGSnapshotAlongsideTheSVG() async throws {
        let renderer = MermaidWebRenderer()
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        let pngData = try #require(diagram.pngData)
        let pngMagicBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagicBytes)
        #expect(pngData.count > 100)
        await renderer.shutdown()
    }

    @Test @MainActor func canvasUsesNegativeOriginAndCommaSeparatedExponentViewBoxForPNG() async throws {
        let probe = try await Self.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10,-20,3.2e2,1.8e2"><circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="-10" y="-20" width="320" height="180" fill="#FFFFFF""##))
        let png = try Self.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try Self.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsMissing() async throws {
        let probe = try await Self.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="320" height="180" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try Self.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try Self.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsInvalid() async throws {
        let probe = try await Self.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 -320 180" width="240" height="135"><circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 240)
        #expect(probe.height == 135)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="240" height="135" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try Self.pngDimensions(probe.pngData)
        #expect(png.width == 480)
        #expect(png.height == 270)
        let pixels = try Self.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test func pieChartsUseDistinctCategoricalSliceColors() async throws {
        let renderer = MermaidWebRenderer()
        let diagram = try await renderer.render(
            Self.fence("pie title Categories\n    \"One\" : 1\n    \"Two\" : 2\n    \"Three\" : 3\n    \"Four\" : 4\n    \"Five\" : 5\n    \"Six\" : 6\n    \"Seven\" : 7\n    \"Eight\" : 8\n    \"Nine\" : 9\n    \"Ten\" : 10\n    \"Eleven\" : 11\n    \"Twelve\" : 12"),
            context: Self.context
        )
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#4E79A7"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#F28E2B"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#59A14F"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#E15759"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#B07AA1"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#76B7B2"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#EDC949"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#FF9DA7"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#9C755F"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#BAB0AC"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#86BCB6"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*fill="#D37295"[^>]*class="pieCircle""##, options: [.regularExpression, .caseInsensitive]) != nil)
        let sliceCount = diagram.svg.components(separatedBy: "class=\"pieCircle\"").count - 1
        let legendSwatchCount = diagram.svg.components(separatedBy: "class=\"legend\"").count - 1
        #expect(sliceCount == 12)
        #expect(legendSwatchCount >= 12)
        #expect(diagram.svg.range(of: ##"<g class="legend"[^>]*>.*fill: rgb\(78, 121, 167\)"##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<g class="legend"[^>]*>.*fill: rgb\(242, 142, 43\)"##, options: [.regularExpression, .caseInsensitive]) != nil)
        #expect(diagram.svg.range(of: ##"<g class="legend"[^>]*>.*fill: rgb\(89, 161, 79\)"##, options: [.regularExpression, .caseInsensitive]) != nil)
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = MermaidWebRenderer()
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("graph TD; A-->"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = MermaidWebRenderer(poolSize: 1)
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("not a diagram at all {{{"), context: Self.context)
        }
        // The same (only) pooled page must still work for the next request —
        // a failed render must not leave the page in a poisoned state.
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func samePooledPageUsesNeutralLightContextAcrossThemeInputs() async throws {
        let renderer = MermaidWebRenderer(poolSize: 1)
        let light = Self.context
        let dark = MermaidRenderContext(
            foregroundRed: 0xEE / 255.0, foregroundGreen: 0xDD / 255.0, foregroundBlue: 0xCC / 255.0,
            backgroundRed: 0x11 / 255.0, backgroundGreen: 0x22 / 255.0, backgroundBlue: 0x33 / 255.0
        )
        let lightSVG = try await renderer.render(Self.fence("graph TD; A-->B;"), context: light).svg
        let darkSVG = try await renderer.render(Self.fence("graph TD; A-->B;"), context: dark).svg
        let lightAgainSVG = try await renderer.render(Self.fence("graph TD; A-->B;"), context: light).svg
        #expect(lightSVG.localizedCaseInsensitiveContains("#1A1A1A"))
        #expect(lightSVG.localizedCaseInsensitiveContains("#ffffff"))
        #expect(darkSVG.localizedCaseInsensitiveContains("#1A1A1A"))
        #expect(darkSVG.localizedCaseInsensitiveContains("#ffffff"))
        #expect(lightAgainSVG.localizedCaseInsensitiveContains("#1A1A1A"))
        #expect(lightAgainSVG.localizedCaseInsensitiveContains("#ffffff"))
        await renderer.shutdown()
    }

    @Test func nonFiniteAndOutOfRangeComponentsNormalizeSafely() async throws {
        let renderer = MermaidWebRenderer()
        let context = MermaidRenderContext(
            foregroundRed: .nan, foregroundGreen: .infinity, foregroundBlue: -.infinity,
            backgroundRed: 2, backgroundGreen: -1, backgroundBlue: .nan
        )
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: context)
        #expect(diagram.svg.localizedCaseInsensitiveContains("#1A1A1A"))
        #expect(diagram.svg.localizedCaseInsensitiveContains("#ffffff"))
        #expect(!diagram.svg.localizedCaseInsensitiveContains("nan"))
        #expect(!diagram.svg.localizedCaseInsensitiveContains("infinity"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = MermaidWebRenderer(timeout: .milliseconds(1))
        await #expect(throws: MermaidRenderError.timedOut) {
            _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = MermaidWebRenderer(maxOutputBytes: 10)
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        let renderer = MermaidWebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedMermaidDiagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(Self.fence("graph TD; A-->B\(index);"), context: Self.context)
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
        let renderer = MermaidWebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        await renderer.shutdown()
        // A fresh page must be created on demand, not left permanently torn down.
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    /// Directly verifies the §10 trust-boundary assumption this epic relies
    /// on, rather than merely asserting it in prose: Mermaid's
    /// `securityLevel: 'strict'` (set in the bundled harness's `render.js`)
    /// must suppress `click` interaction directives, so a diagram attempting
    /// one never produces a live, callable interaction in the output SVG.
    @Test func strictSecurityLevelSuppressesClickDirectives() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        graph TD
            A-->B
            click A "javascript:alert(1)"
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(!diagram.svg.contains("javascript:alert"))
        await renderer.shutdown()
    }

    /// Adversarial corpus (epic-20-implementation.md §15): a genuinely
    /// larger, more realistic diagram — not just a two-node smoke test —
    /// to catch problems that only appear with real layout complexity
    /// (long render time, degenerate output, a raster snapshot too small
    /// to be useful). 12 nodes, a cluster, and multiple edge label styles.
    @Test func renderHandlesAModeratelyComplexDiagramWithinTheDefaultTimeout() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        graph TD
            Start[Start] --> Auth{Authenticated?}
            Auth -->|No| Login[Show Login]
            Login --> Auth
            Auth -->|Yes| Dashboard[Dashboard]
            subgraph Processing
                Dashboard --> Fetch[Fetch Data]
                Fetch --> Validate{Valid?}
                Validate -->|No| Error[Show Error]
                Validate -->|Yes| Transform[Transform Data]
                Transform --> Cache[(Cache)]
            end
            Cache --> Render[Render View]
            Error --> Dashboard
            Render --> End([Done])
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        let pngData = try #require(diagram.pngData)
        #expect(pngData.count > 1000)
        await renderer.shutdown()
    }

    /// Adversarial corpus: whitespace-only source is not valid Mermaid
    /// syntax and must fail the same safe, diagnosable way as any other
    /// malformed input — never hang, never crash, never produce an empty
    /// but "successful" diagram.
    @Test func renderFailsSafelyOnWhitespaceOnlySource() async throws {
        let renderer = MermaidWebRenderer()
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("   \n\n   "), context: Self.context)
        }
        await renderer.shutdown()
    }
}
