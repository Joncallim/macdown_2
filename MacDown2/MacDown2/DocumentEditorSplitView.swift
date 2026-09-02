import AppKit
import AppSettings
import Contributions
import EditorCore
import FileCore
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Themes
import UniformTypeIdentifiers
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
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let scrollController: ScrollSyncController
    let outlineController: OutlineController

    @Environment(\.windowCoordinator) var coordinator
    @Environment(\.appSettings) private var appSettings

    // Not `private`: read by DocumentEditorSplitView+Divider.swift, split
    // out to stay under the type-body-length lint budget (matches
    // DocumentEditorSplitView+AppSettings.swift's same reason).
    @State var dragOriginFraction: Double?
    @State private var previewBlocks: [PreviewBlock]?
    @State private var previewLinkDefinitions: [String] = []
    @State private var contributionResults: [ContributionResult] = []

    private var parseSession: MarkdownParseSession {
        parseStore.session(for: identity)
    }

    private var jsonSession: JSONAnalysisSession {
        jsonAnalysisStore.session(for: identity)
    }

    /// D7: gates the outline on format, not just its label — a Python or
    /// shell file's `# comment` lines are still parsed as Markdown headings
    /// by `parseSession`, and this is what keeps them out of the sidebar.
    private var isMarkdown: Bool {
        PreviewRouter.previewKind(for: document.format) == .markdown
    }

    /// D7/E11: the JSON outline channel is gated on the exact JSON format id,
    /// mirroring the Markdown gate above.
    private var isJSON: Bool {
        document.format.id == "json"
    }

    private var previewLayout: PreviewLayoutMode {
        tab.previewLayout ?? Self.defaultPreviewLayout(from: appSettings?.previewExport)
    }

    var currentSplitFraction: Double? {
        switch previewLayout {
        case let .split(fraction): fraction
        case .editorOnly, .previewOnly: nil
        }
    }

    private var editorConfiguration: EditorConfiguration {
        var config = EditorConfiguration.default
        if let editorSettings = appSettings?.editor {
            config.font = Self.resolvedFont(from: editorSettings.font)
            config.wrapsLines = editorSettings.wrapsLines
            config.showsInvisibles = editorSettings.showsInvisibles
        }
        config.scrollsPastEnd = false
        // E10 is Markdown-only and fails closed: the default is disabled, and
        // only the exact Markdown format id receives the Markdown assists.
        // `WindowController` eagerly creates a text system with `.default`
        // before this format-specific configuration arrives, so a JSON/HTML/
        // source file can never receive a transient Markdown assist.
        config.editingAssists = document.format.id == "markdown"
            ? Self.assistConfiguration(from: appSettings?.editor)
            : .disabled
        return config
    }

    var body: some View {
        splitContent
            .task(id: identity) {
                await loadInitialContent()
            }
            .onChange(of: text) { _, newText in
                parseSession.textDidChange(newText)
                jsonSession.textDidChange(newText)
            }
            .onChange(of: document.format.id) { _, _ in
                // Save As format transitions re-gate both outline channels so
                // a stale Markdown outline never survives a move to JSON (and
                // vice versa), and invalidate a persisted preview mode the new
                // format cannot display.
                refreshOutline()
                refreshJSONOutline()
                resetInvalidPreviewMode()
            }
            .onChange(of: parseSession.document) { _, _ in
                refreshPreviewBlocks()
                refreshOutline()
            }
            .task(id: parseSession.document) {
                contributionResults = await PreviewContributionAdapter.results(
                    document: parseSession.document,
                    text: parseSession.publishedText,
                    generation: document.mutationGeneration
                )
            }
            .onChange(of: jsonSession.result) { _, _ in
                refreshJSONOutline()
            }
            .onChange(of: appSettings?.markdown) { _, newValue in
                parseSession.setOptions(Self.markdownParseOptions(from: newValue))
            }
    }

    /// The editor/preview split. Split from `body` (and the observation
    /// modifiers kept in `body`) so the compiler can type-check each chain.
    private var splitContent: some View {
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
        .onChange(of: outlineController.pendingJSONJumpSourceRange) { _, sourceRange in
            guard let sourceRange else { return }
            let nsRange = NSRange(sourceRange)
            editorStore.existingSystem(for: identity)?.revealSelection(utf16Range: nsRange, flash: true, animated: true)
            outlineController.pendingJSONJumpSourceRange = nil
        }
    }

    /// Initial content load: parse both sessions immediately (bypassing the
    /// debounce) and refresh both outline channels. Split out of `.task(id:)`
    /// so the compiler can type-check the view body.
    private func loadInitialContent() async {
        parseSession.setOptions(Self.markdownParseOptions(from: appSettings?.markdown))
        await parseSession.parseNow(text)
        refreshPreviewBlocks()
        refreshOutline()
        await jsonSession.analyzeNow(text)
        refreshJSONOutline()
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

    /// E11: a pure readout of the JSON analysis session. The format gate
    /// lives in the controller (`formatID == "json"`), so a Save As away
    /// from JSON clears the channel.
    private func refreshJSONOutline() {
        outlineController.updateJSON(
            result: jsonSession.result,
            formatID: document.format.id
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
                outlineController.jsonReferenceOffsetDidChange(range.location)
            },
            onScrollChange: { offset in
                handleEditorScroll(utf16Offset: offset)
                outlineController.jsonReferenceOffsetDidChange(offset)
            }
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
                blocks: PreviewContributionAdapter.merged(
                    base: previewBlocks,
                    contributions: contributionResults,
                    sourceMap: parseSession.document?.sourceMap,
                    currentGeneration: document.mutationGeneration
                ),
                linkDefinitions: previewLinkDefinitions
            )
            .overlay(alignment: .topTrailing) { PreviewBusyIndicator(isVisible: parseSession.isParsing) }
        case .html:
            HTMLPreviewPane(model: model, tab: tab, document: document, text: text)
        case .jsonOutline:
            // The JSON preview mode IS the outline: the same format-neutral
            // tree the sidebar shows, with collapse/selection/jump state
            // shared through `outlineController`. The leaf-level identifiers
            // (`jsonOutlinePreviewPane`, `jsonInvalidState`) live inside
            // `JSONOutlinePreviewView`.
            JSONOutlinePreviewView(outlineController: outlineController)
                .overlay(alignment: .topTrailing) { PreviewBusyIndicator(isVisible: jsonSession.isAnalyzing) }
        case .none:
            NoPreviewView(formatName: document.format.name)
        }
    }

    /// Save As invalidation: a persisted preview mode the new format cannot
    /// display is dropped (back to the format default) and the session is
    /// re-saved so the stale mode is not restored after relaunch.
    private func resetInvalidPreviewMode() {
        guard let mode = tab.previewMode, !PreviewRouter.supports(mode, for: document.format) else { return }
        model.tabStore.setPreviewMode(nil, for: tab.id)
        coordinator?.scheduleSaveSession()
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
        .accessibilityIdentifier("noPreviewPane")
    }
}
