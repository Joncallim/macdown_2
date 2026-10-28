import AppKit
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import SwiftUI
import Textual
import Themes

/// Split out from `TextualMarkdownPreview.swift` purely to stay under
/// SwiftLint's `file_length` limit, matching this package's own
/// `DocumentEditorSplitView+Mermaid.swift` precedent (app target) for
/// splitting a large view's supporting code into its own file.
struct BlockView: View {
    let block: PreviewBlock
    let theme: PreviewTheme
    let linkResolver: PreviewLinkResolver
    let resourceImageLoader: PreviewResourceImageLoader?
    let resourceLoadID: UUID?
    @Environment(\.previewOpenDocument) private var openDocument
    let definitionIndex: PreviewLinkDefinitionIndex
    let mermaidFenceView: ((String) -> AnyView)?
    let d2FenceView: ((String) -> AnyView)?
    let graphvizFenceView: ((String) -> AnyView)?

    /// The block's source with every document-wide link reference definition
    /// prepended, so a `[text][label]` reference in this block resolves even
    /// when `label` is defined in a different block. See
    /// ``PreviewLinkDefinitions``. Oversize blocks skip this — they already
    /// bypass Textual entirely.
    private var renderedSource: String {
        definitionIndex.prefixed(block.source)
    }

    /// `block.source` for a `.codeBlock` includes both fence delimiter
    /// lines (confirmed against `PreviewBlock.blocks(from:text:)`'s own
    /// slicing) — stripped here via the same helper `MermaidFenceScanner`
    /// uses for Export, so both paths recover identical diagram source from
    /// differently-produced but identically-sliced text.
    private var mermaidFenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, language.caseInsensitiveCompare("mermaid") == .orderedSame
        else { return nil }
        return MermaidFenceContent.stripDelimiters(from: block.source)
    }

    private var d2FenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, language.caseInsensitiveCompare("d2") == .orderedSame
        else { return nil }
        return D2FenceContent.stripDelimiters(from: block.source)
    }

    private static let graphvizLanguages: Set<String> = ["dot", "graphviz"]

    private var graphvizFenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, Self.graphvizLanguages.contains(language.lowercased())
        else { return nil }
        return GraphvizFenceContent.stripDelimiters(from: block.source)
    }

    var body: some View {
        Group {
            if block.isOversize {
                // Oversize blocks skip Textual entirely: it has no size limit
                // of its own and is documented to freeze/crash on inputs
                // around 100 KB (see ``PreviewBlock/oversizeByteThreshold``).
                OversizeTextView(source: block.source)
            } else if let mermaidFenceSource, let mermaidFenceView {
                mermaidFenceView(mermaidFenceSource)
            } else if let d2FenceSource, let d2FenceView {
                d2FenceView(d2FenceSource)
            } else if let graphvizFenceSource, let graphvizFenceView {
                graphvizFenceView(graphvizFenceSource)
            } else {
                // `baseURL` resolves relative image sources (e.g.
                // `![plot](images/plot.png)`) during parsing. `linkResolver`
                // carries the same document base URL used to resolve clicked
                // links, so both paths agree on what "relative" means.
                secureOrLegacyText
                    .tint(theme.linkColor.swiftUIColor)
                    .environment(
                        \.openURL,
                        OpenURLAction { url in
                            let resolved = linkResolver.resolve(url)
                            switch PreviewLinkResolver.action(for: resolved, currentDocument: linkResolver.baseURL) {
                            case .open: NSWorkspace.shared.open(resolved)
                            case let .openInApp(document):
                                // Through MostlyText when the host provides it; otherwise the
                                // default handler for a text document.
                                if let openDocument {
                                    openDocument(document)
                                } else {
                                    NSWorkspace.shared.open(document)
                                }
                            case .reveal: NSWorkspace.shared.activateFileViewerSelecting([resolved])
                            case .ignore: break
                            }
                            return .handled
                        }
                    )
            }
        }
        .foregroundStyle(theme.foreground.swiftUIColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var secureOrLegacyText: some View {
        let source = renderedSource
        let text = StructuredText(
            source,
            parser: PreviewMarkupParser(baseURL: linkResolver.baseURL, syntaxExtensions: [.math])
        )
        // Textual's attachment overlay can retain old symbol geometry when
        // an existing block gains or changes inline math. Remount only blocks
        // with a possible math delimiter when their parsed input changes;
        // the outer PreviewBlock ID stays stable for scroll position and sync.
        let mathContentID = Self.inlineMathContentID(blockSource: block.source, renderedSource: source)
        let content = text.id(mathContentID)
        if let resourceImageLoader {
            // Textual keys its attachment task only by attributed text and can publish after cancellation.
            // A new resource identity must therefore replace its complete state subtree.
            content.id(resourceLoadID)
                .textual.imageAttachmentLoader(resourceImageLoader)
                .textual.emojiAttachmentLoader(resourceImageLoader)
                .textual.textSelection(.enabled)
        } else {
            content
        }
    }

    static func inlineMathContentID(blockSource: String, renderedSource: String) -> String {
        blockSource.contains("$") ? renderedSource : ""
    }
}

private struct OversizeTextView: View {
    let source: String
    @State private var chunks: [String]

    init(source: String) {
        self.source = source
        _chunks = State(initialValue: OversizeTextChunker.displayChunks(source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .onChange(of: source) { _, newSource in
            chunks = OversizeTextChunker.displayChunks(newSource)
        }
    }
}

// MARK: - Helpers

extension ThemeColor {
    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
