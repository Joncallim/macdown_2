import DiagramsD2
import DiagramWebKitPool
import Foundation

/// The real, WebKit-backed implementation of `D2DiagramRendering`
/// (epic-21-implementation.md §3.2), built on the shared
/// `DiagramWebKitPool`/`DiagramHarnessPage` infrastructure rather than
/// reimplementing pool/checkout/timeout logic (§3.1, §3.3).
public actor D2WebRenderer: D2DiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private let pool: DiagramWebKitPool
    private let maxOutputBytes: Int

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = D2WebRenderer.defaultMaxOutputBytes
    ) {
        pool = DiagramWebKitPool(
            harnessResourceName: "harness",
            bundle: Bundle.module,
            poolSize: poolSize,
            timeout: timeout
        )
        self.maxOutputBytes = maxOutputBytes
    }

    /// `context`'s theme colors are accepted but not yet passed through
    /// to D2's own theming — the same disclosed, deliberate scope limit
    /// already recorded for Mermaid (issue #79).
    public func render(_ fence: D2Fence, context _: D2RenderContext) async throws -> RenderedD2Diagram {
        let diagram = try await withPoolErrorMapping {
            try await pool.withPage { page in
                try await Self.render(fence, on: page)
            }
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= maxOutputBytes else {
            throw D2RenderError.outputTooLarge(byteCount: byteCount)
        }
        return diagram
    }

    public func shutdown() async {
        await pool.shutdown()
    }

    @MainActor
    private static func render(_ fence: D2Fence, on page: DiagramHarnessPage) async throws -> RenderedD2Diagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderD2(source);",
            arguments: ["source": fence.source]
        )
        guard let dict = result as? [String: Any], let succeeded = dict["ok"] as? Bool else {
            throw D2RenderError.rendererUnavailable
        }
        guard succeeded else {
            let message = (dict["message"] as? String) ?? "unknown error"
            throw D2RenderError.invalidSyntax(message)
        }
        guard let svg = dict["svg"] as? String else {
            throw D2RenderError.rendererUnavailable
        }
        let width = (dict["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (dict["height"] as? NSNumber)?.doubleValue ?? 0
        return RenderedD2Diagram(svg: svg, naturalWidth: width, naturalHeight: height)
    }

    /// Maps the shared pool's generic errors to this language's own
    /// domain error type, matching `MermaidWebRenderer`'s own
    /// single-domain-error convention.
    private func withPoolErrorMapping<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch DiagramPoolError.timedOut {
            throw D2RenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw D2RenderError.rendererUnavailable
        }
    }
}
