import DiagramsGraphviz
import DiagramWebKitPool
import Foundation

/// The real, WebKit-backed implementation of `GraphvizDiagramRendering`
/// (epic-21-implementation.md §3.2), built on the shared
/// `DiagramWebKitPool`/`DiagramHarnessPage` infrastructure.
public actor GraphvizWebRenderer: GraphvizDiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private var pool: DiagramWebKitPool?
    private var retirement: (id: UUID, task: Task<Void, Never>)?
    private let poolSize: Int
    private let timeout: Duration
    private let maxOutputBytes: Int

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = GraphvizWebRenderer.defaultMaxOutputBytes
    ) {
        self.poolSize = poolSize
        self.timeout = timeout
        pool = DiagramWebKitPool(
            harnessResourceName: "harness",
            bundle: Bundle.module,
            poolSize: poolSize,
            timeout: timeout
        )
        self.maxOutputBytes = maxOutputBytes
    }

    public func render(_ fence: GraphvizFence,
                       context: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        let activePool = try availablePool()
        let diagram = try await withPoolErrorMapping {
            try await activePool.withPage { page in
                try await Self.render(fence, context: context, on: page)
            }
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= maxOutputBytes else {
            throw GraphvizRenderError.outputTooLarge(byteCount: byteCount)
        }
        return diagram
    }

    public func shutdown() async {
        if retirement != nil {
            await finishRetirement()
            return
        }
        guard let retiring = pool else { return }
        pool = nil
        retirement = (UUID(), Task { await retiring.shutdown() })
        await finishRetirement()
    }

    private func availablePool() throws -> DiagramWebKitPool {
        try Task.checkCancellation()
        guard retirement == nil else { throw GraphvizRenderError.rendererUnavailable }
        if let pool {
            return pool
        }
        let fresh = DiagramWebKitPool(
            harnessResourceName: "harness", bundle: Bundle.module,
            poolSize: poolSize, timeout: timeout
        )
        pool = fresh
        return fresh
    }

    private func finishRetirement() async {
        guard let current = retirement else { return }
        await current.task.value
        if retirement?.id == current.id {
            retirement = nil
        }
    }

    @MainActor
    private static func render(_ fence: GraphvizFence,
                               context: GraphvizRenderContext,
                               on page: DiagramHarnessPage) async throws -> RenderedGraphvizDiagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderGraphviz(source, theme);",
            arguments: [
                "source": fence.source,
                "theme": [
                    "foreground": context.foregroundHex,
                    "background": context.backgroundHex,
                ],
            ]
        )
        guard result.succeeded else {
            let message = result.message ?? "unknown error"
            throw GraphvizRenderError.invalidSyntax(message)
        }
        guard let svg = result.svg else {
            throw GraphvizRenderError.rendererUnavailable
        }
        return RenderedGraphvizDiagram(svg: svg, naturalWidth: result.width, naturalHeight: result.height)
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

private extension GraphvizRenderContext {
    var foregroundHex: String {
        hex(red: foregroundRed, green: foregroundGreen, blue: foregroundBlue)
    }

    var backgroundHex: String {
        hex(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
    }

    func hex(red: Double, green: Double, blue: Double) -> String {
        let components = [red, green, blue].map { value in
            let finite = value.isFinite ? value : 0
            return UInt8((min(max(finite, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }
}
