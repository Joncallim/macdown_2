import DiagramsGraphviz
import DiagramWebKitPool
import Foundation

/// The real, WebKit-backed implementation of `GraphvizDiagramRendering`
/// (epic-21-implementation.md §3.2), built on the shared
/// `DiagramWebKitPool`/`DiagramHarnessPage` infrastructure.
public actor GraphvizWebRenderer: GraphvizDiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private let pool: DiagramWebKitPool
    private let maxOutputBytes: Int

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = GraphvizWebRenderer.defaultMaxOutputBytes
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
    /// to Graphviz's own theming — the same disclosed, deliberate scope
    /// limit already recorded for Mermaid (issue #79).
    public func render(_ fence: GraphvizFence,
                       context _: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        let diagram = try await withPoolErrorMapping {
            try await pool.withPage { page in
                try await Self.render(fence, on: page)
            }
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= maxOutputBytes else {
            throw GraphvizRenderError.outputTooLarge(byteCount: byteCount)
        }
        return diagram
    }

    public func shutdown() async {
        await pool.shutdown()
    }

    @MainActor
    private static func render(_ fence: GraphvizFence,
                               on page: DiagramHarnessPage) async throws -> RenderedGraphvizDiagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderGraphviz(source);",
            arguments: ["source": fence.source]
        )
        guard let dict = result as? [String: Any], let succeeded = dict["ok"] as? Bool else {
            throw GraphvizRenderError.rendererUnavailable
        }
        guard succeeded else {
            let message = (dict["message"] as? String) ?? "unknown error"
            throw GraphvizRenderError.invalidSyntax(message)
        }
        guard let svg = dict["svg"] as? String else {
            throw GraphvizRenderError.rendererUnavailable
        }
        let width = (dict["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (dict["height"] as? NSNumber)?.doubleValue ?? 0
        return RenderedGraphvizDiagram(svg: svg, naturalWidth: width, naturalHeight: height)
    }

    private func withPoolErrorMapping<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch DiagramPoolError.timedOut {
            throw GraphvizRenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw GraphvizRenderError.rendererUnavailable
        }
    }
}
