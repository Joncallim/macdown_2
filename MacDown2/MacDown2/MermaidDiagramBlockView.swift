import AppKit
import Diagrams
import SwiftUI

/// Renders one ```mermaid``` fence's diagram inline in the native preview
/// (epic-20-implementation.md §7.2). Displays `RenderedMermaidDiagram.pngData`
/// — a real WebKit-rendered raster snapshot, not `svg` — because AppKit's
/// own SVG decoder cannot reliably display real Mermaid output (see the
/// Slice 4 as-built note at the top of the architecture document, and
/// `RenderedMermaidDiagram`'s own doc comment for the full finding).
/// `svg` remains genuinely vector and is what Export/copy-as-SVG use; this
/// view never touches it.
struct MermaidDiagramBlockView: View {
    let source: String
    let context: MermaidRenderContext
    let renderer: any MermaidDiagramRendering

    private enum RenderState {
        case loading
        case rendered(NSImage, width: Double, height: Double)
        case failed(String)
    }

    @State private var renderState: RenderState = .loading

    var body: some View {
        Group {
            switch renderState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                    .accessibilityIdentifier("mermaidDiagramLoading")
            case let .rendered(image, width, height):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(width, 640), maxHeight: height)
                    .accessibilityLabel(Text(source))
                    .accessibilityIdentifier("mermaidDiagramImage")
            case let .failed(message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("This diagram could not be rendered.")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
                .accessibilityIdentifier("mermaidDiagramError")
                .help(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: source) {
            await render()
        }
    }

    private func render() async {
        let fence = MermaidFence(source: source, sourceRange: 0 ..< 0)
        do {
            let diagram = try await renderer.render(fence, context: context)
            guard !Task.isCancelled else { return }
            guard let pngData = diagram.pngData, let image = NSImage(data: pngData) else {
                renderState = .failed("no preview image was produced")
                return
            }
            renderState = .rendered(image, width: diagram.naturalWidth, height: diagram.naturalHeight)
        } catch {
            guard !Task.isCancelled else { return }
            renderState = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let renderError = error as? MermaidRenderError else {
            return error.localizedDescription
        }
        switch renderError {
        case let .invalidSyntax(message): return message
        case .timedOut: return "rendering timed out"
        case let .outputTooLarge(byteCount): return "rendered output too large (\(byteCount) bytes)"
        case .rendererUnavailable: return "renderer unavailable"
        }
    }
}
