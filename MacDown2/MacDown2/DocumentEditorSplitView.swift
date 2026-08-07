import EditorCore
import FileCore
import Highlighting
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Themes
import WebKit
import Workspace

// MARK: - Source / preview split

struct DocumentEditorSplitView: View {
    let model: WorkspaceModel
    let document: FileCore.FileDocument
    let tab: WorkspaceTab
    let identity: String
    @Binding var text: String
    let editorStore: EditorTextSystemStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let themeController: ThemeController
    let scrollController: ScrollSyncController
    let outlineController: OutlineController

    @Environment(\.windowCoordinator) private var coordinator

    @State private var dragOriginFraction: Double?
    @State private var previewBlocks: [PreviewBlock]?
    @State private var previewLinkDefinitions: [String] = []

    private var parseSession: MarkdownParseSession {
        parseStore.session(for: identity)
    }

    /// D7: gates the outline on format, not just its label — a Python or
    /// shell file's `# comment` lines are still parsed as Markdown headings
    /// by `parseSession`, and this is what keeps them out of the sidebar.
    private var isMarkdown: Bool {
        PreviewRouter.previewKind(for: document.format) == .markdown
    }

    private var previewLayout: PreviewLayoutMode {
        tab.previewLayout ?? .defaultMode
    }

    private var currentSplitFraction: Double? {
        switch previewLayout {
        case let .split(fraction): fraction
        case .editorOnly, .previewOnly: nil
        }
    }

    private var editorConfiguration: EditorConfiguration {
        var config = EditorConfiguration.default
        config.scrollsPastEnd = false
        return config
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if previewLayout.showsEditor {
                    editorPane
                        .frame(width: PreviewPaneWidths.editorWidth(in: geometry.size.width, layout: previewLayout))
                }

                if previewLayout.showsEditor, previewLayout.showsPreview {
                    divider(in: geometry)
                }

                if previewLayout.showsPreview {
                    previewPane
                        .accessibilityIdentifier("previewPane")
                        .frame(width: PreviewPaneWidths.previewWidth(in: geometry.size.width, layout: previewLayout))
                }
            }
        }
        .task(id: identity) {
            await parseSession.parseNow(text)
            refreshPreviewBlocks()
            refreshOutline()
        }
        .onChange(of: text) { _, newText in
            parseSession.textDidChange(newText)
        }
        .onChange(of: parseSession.document) { _, _ in
            refreshPreviewBlocks()
            refreshOutline()
        }
        .onChange(of: scrollController.targetSourceLine) { _, line in
            guard let line, let sourceMap = parseSession.document?.sourceMap else { return }
            let range = sourceMap.utf16Range(ofLines: line ... line)
            editorStore.existingSystem(for: identity)?.scrollToVisible(utf16Range: range)
            scrollController.targetSourceLine = nil
        }
        .onChange(of: outlineController.pendingJumpLineRange) { _, lineRange in
            guard let lineRange, let sourceMap = parseSession.document?.sourceMap else { return }
            let range = sourceMap.utf16Range(ofLines: lineRange)
            // Both sides are told the same source line directly, rather than
            // the editor deriving its target and the preview reading back
            // where the editor landed — see `ScrollSyncController.jump(toLine:)`
            // for why that round trip is fragile for a jump this large.
            scrollController.jump(toLine: lineRange.lowerBound)
            editorStore.existingSystem(for: identity)?.revealSelection(utf16Range: range, flash: true, animated: true)
            outlineController.pendingJumpLineRange = nil
        }
    }

    private func refreshPreviewBlocks() {
        guard let document = parseSession.document, let text = parseSession.publishedText else {
            previewBlocks = nil
            previewLinkDefinitions = []
            return
        }
        previewBlocks = PreviewBlock.blocks(from: document, text: text)
        previewLinkDefinitions = PreviewLinkDefinitions.extract(from: text)
    }

    /// D2: no parse of its own — a pure readout of the same `parseSession`
    /// the preview already reads.
    private func refreshOutline() {
        outlineController.update(
            document: parseSession.document,
            isMarkdown: isMarkdown,
            formatName: document.format.name
        )
    }

    /// Forwards the editor's visible top line into the scroll-sync
    /// controller so the preview follows. `utf16Offset` comes from
    /// `EditorView`'s scroll callback (see `EditorTextSystem.topVisibleUTF16Offset`).
    ///
    /// Skips the outline update while `scrollController.isJumping`: an
    /// animated `revealSelection` (the outline's own jump) fires this
    /// callback once per frame of its ~0.2s scroll animation, and those
    /// mid-flight offsets don't yet reflect the jump's target — reading them
    /// back into the outline overwrote the correct highlight (already set
    /// synchronously by the jump's own selection change, below in
    /// `pendingJumpLineRange`) with a stale one, leaving the *previous*
    /// heading bolded after a jump landed correctly.
    private func handleEditorScroll(utf16Offset: Int) {
        guard let sourceMap = parseSession.document?.sourceMap else { return }
        scrollController.editorDidScroll(toLine: sourceMap.line(atUTF16Offset: utf16Offset))
        guard !scrollController.isJumping else { return }
        outlineController.referenceOffsetDidChange(utf16Offset)
    }

    private var editorPane: some View {
        EditorView(
            text: $text,
            identity: identity,
            configuration: editorConfiguration,
            store: editorStore,
            onSelectionChange: { range in
                outlineController.referenceOffsetDidChange(range.location)
            },
            onScrollChange: handleEditorScroll
        )
        .accessibilityIdentifier("editorPane")
        .task(id: identity) {
            attachHighlighter()
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        switch PreviewRouter.previewKind(for: document.format) {
        case .markdown:
            TextualMarkdownPreview(
                document: parseSession.document,
                text: parseSession.publishedText,
                theme: PreviewTheme(theme: themeController.current),
                linkResolver: PreviewLinkResolver(baseURL: document.fileURL),
                controller: scrollController,
                blocks: previewBlocks,
                linkDefinitions: previewLinkDefinitions
            )
        case .html:
            HTMLPreviewView(text: $text)
        case .none:
            NoPreviewView(formatName: document.format.name)
        }
    }

    private func divider(in geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: dividerWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let total = geometry.size.width
                        guard total > 0 else { return }
                        if dragOriginFraction == nil {
                            guard let currentSplitFraction else {
                                assertionFailure("Drag origin captured in non-split layout")
                                return
                            }
                            dragOriginFraction = currentSplitFraction
                        }
                        let fraction = (dragOriginFraction ?? 0.5) + value.translation.width / total
                        model.tabStore.setPreviewLayout(
                            .split(fraction: fraction),
                            for: tab.id
                        )
                        coordinator?.scheduleSaveSession()
                    }
                    .onEnded { _ in
                        dragOriginFraction = nil
                    }
            )
            .accessibilityLabel("Resize editor and preview")
    }

    private func attachHighlighter() {
        guard let textSystem = editorStore.existingSystem(for: identity) else { return }
        _ = highlightStore.highlighter(
            for: identity,
            textSystem: textSystem,
            languageID: document.format.highlightLanguageID,
            theme: themeController.current
        )
    }
}

// MARK: - HTML preview

private struct HTMLPreviewView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Disable content JavaScript for every navigation. `preferences.javaScriptEnabled`
        // is deprecated (macOS 11+); the per-configuration replacement is
        // `defaultWebpagePreferences.allowsContentJavaScript`. This is defence-in-depth
        // on top of the CSP injected by `PreviewSecurity.hardenedHTMLDocument(from:)`.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        // Inject a restrictive CSP so a previewed file cannot load remote
        // resources (defence-in-depth on top of the disabled JavaScript above).
        webView.loadHTMLString(PreviewSecurity.hardenedHTMLDocument(from: text), baseURL: nil)
    }
}

// MARK: - No preview

private struct NoPreviewView: View {
    let formatName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No preview for \(formatName)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
