import EditorCore
import FileCore
import Highlighting
import MarkdownEngine
import Preview
import SwiftUI
import Themes
import WebKit
import Workspace

struct ContentAreaView: View {
    let model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let themeController: ThemeController

    @State private var scrollController = ScrollSyncController()

    var body: some View {
        content(
            for: model.activeDocument,
            tab: model.tabStore.activeTab,
            identity: activeIdentity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(
        for document: FileCore.FileDocument?,
        tab: WorkspaceTab?,
        identity: String?
    ) -> some View {
        if let document, let tab, let identity {
            documentContent(document, tab: tab, identity: identity)
        } else {
            emptyState
        }
    }

    private var activeIdentity: String? {
        model.tabStore.activeTabID?.uuidString
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.activeDocument?.text ?? "" },
            set: { newText in
                model.tabStore.updateActiveDocument { $0.edited(text: newText) }
            }
        )
    }

    private func documentContent(
        _ document: FileCore.FileDocument,
        tab: WorkspaceTab,
        identity: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Image(systemName: documentIcon(for: document.format.id))
                    .foregroundStyle(.secondary)

                Text(title(for: document))
                    .font(.system(size: 13, weight: .semibold))

                if document.fileURL == nil {
                    Text("— Save As… ⌘⇧S to name this document")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Format badge
                Text(document.format.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Source / preview split
            DocumentEditorSplitView(
                model: model,
                document: document,
                tab: tab,
                identity: identity,
                text: textBinding,
                editorStore: editorStore,
                highlightStore: highlightStore,
                parseStore: parseStore,
                themeController: themeController,
                scrollController: scrollController
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.quaternary)

            Text("No Document")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ShortcutHint(shortcut: "⌘N", label: "New File")
                ShortcutHint(shortcut: "⌘O", label: "Open File")
            }
        }
    }

    private func title(for document: FileCore.FileDocument) -> String {
        document.fileURL?.lastPathComponent ?? "Untitled"
    }

    private func documentIcon(for formatID: String) -> String {
        let sourceIcons: Set = [
            "javascript", "typescript", "python", "ruby",
            "swift", "c", "bash", "sql",
        ]
        if sourceIcons.contains(formatID) {
            return "chevron.left.forwardslash.chevron.right"
        }
        switch formatID {
        case "markdown": return "richtext"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        default: return "doc.text"
        }
    }
}

// MARK: - Source / preview split

private struct DocumentEditorSplitView: View {
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

    @Environment(\.windowCoordinator) private var coordinator

    @State private var dragOriginFraction: Double?
    @State private var previewBlocks: [PreviewBlock]?
    @State private var previewLinkDefinitions: [String] = []

    private var parseSession: MarkdownParseSession {
        parseStore.session(for: identity)
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
        }
        .onChange(of: text) { _, newText in
            parseSession.textDidChange(newText)
        }
        .onChange(of: parseSession.document) { _, _ in
            refreshPreviewBlocks()
        }
        .onChange(of: scrollController.targetSourceLine) { _, line in
            guard let line, let sourceMap = parseSession.document?.sourceMap else { return }
            let range = sourceMap.utf16Range(ofLines: line ... line)
            editorStore.existingSystem(for: identity)?.scrollToVisible(utf16Range: range)
            scrollController.targetSourceLine = nil
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

    /// Forwards the editor's visible top line into the scroll-sync
    /// controller so the preview follows. `utf16Offset` comes from
    /// `EditorView`'s scroll callback (see `EditorTextSystem.topVisibleUTF16Offset`).
    private func handleEditorScroll(utf16Offset: Int) {
        guard let sourceMap = parseSession.document?.sourceMap else { return }
        scrollController.editorDidScroll(toLine: sourceMap.line(atUTF16Offset: utf16Offset))
    }

    private var editorPane: some View {
        EditorView(
            text: $text,
            identity: identity,
            configuration: editorConfiguration,
            store: editorStore,
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

// MARK: - Helpers

private struct ShortcutHint: View {
    let shortcut: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
