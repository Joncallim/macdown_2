import AppSettings
import EditorCore
import FileCore
@testable import MacDown2
import MarkdownEngine
import Testing
import Workspace

@Suite("AppSettings wiring")
@MainActor
struct AppSettingsWiringTests {
    // MARK: - Markdown

    @Test func markdownParseOptionsReflectsThePreference() {
        let enabled = DocumentEditorSplitView.markdownParseOptions(from: MarkdownSettings(parsesBlockDirectives: true))
        #expect(enabled.blockDirectives)

        let disabled = DocumentEditorSplitView.markdownParseOptions(
            from: MarkdownSettings(parsesBlockDirectives: false)
        )
        #expect(!disabled.blockDirectives)
    }

    @Test func markdownParseOptionsLeavesTheInertFieldsAlwaysOn() {
        let options = DocumentEditorSplitView.markdownParseOptions(from: MarkdownSettings(parsesBlockDirectives: false))
        #expect(options.tables)
        #expect(options.taskLists)
        #expect(options.strikethrough)
        #expect(options.autolinks)
        #expect(options.footnotes)
    }

    @Test func markdownParseOptionsDefaultsToOnWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.markdownParseOptions(from: nil).blockDirectives)
    }

    // MARK: - Editor assists

    @Test func assistConfigurationReflectsEveryField() {
        let settings = EditorSettings(
            indentationWidth: 2,
            assistsEnabled: false,
            continuesMarkdownPrefixes: false,
            completesMatchingCharacters: false,
            convertsTabsToSpaces: false,
            smartHome: false,
            autoIncrementOrderedLists: false
        )
        let config = DocumentEditorSplitView.assistConfiguration(from: settings)
        #expect(!config.isEnabled)
        #expect(!config.continuesMarkdownPrefixes)
        #expect(!config.completesMatchingCharacters)
        #expect(!config.convertsTabsToSpaces)
        #expect(!config.smartHome)
        #expect(!config.autoIncrementOrderedLists)
        #expect(config.indentationWidth == 2)
    }

    @Test func assistConfigurationFallsBackToMarkdownDefaultWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.assistConfiguration(from: nil) == .markdownDefault)
    }

    // MARK: - Preview layout

    @Test func defaultPreviewLayoutMapsEachPreference() {
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .editorOnly)
            ) == .editorOnly
        )
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .split)
            ) == .defaultMode
        )
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .previewOnly)
            ) == .previewOnly
        )
    }

    @Test func defaultPreviewLayoutFallsBackToDefaultModeWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.defaultPreviewLayout(from: nil) == .defaultMode)
    }

    // MARK: - Export defaults

    @Test func exportFormatOptionMapsEachPreference() {
        #expect(ExportCoordinator.exportFormatOption(from: .standaloneHTML) == .standaloneHTML)
        #expect(ExportCoordinator.exportFormatOption(from: .selfContainedHTML) == .selfContainedHTML)
        #expect(ExportCoordinator.exportFormatOption(from: .pdf) == .pdf)
    }

    @Test func exportStyleEmbeddingMapsEachPreference() {
        #expect(ExportCoordinator.exportStyleEmbedding(from: .embedded) == .embedded)
        #expect(ExportCoordinator.exportStyleEmbedding(from: .linked) == .linked)
    }

    // MARK: - Format encoding

    @Test func defaultEncodingMapsUTF16ToTheLittleEndianBOMForm() {
        let resolved = WindowCoordinator.defaultEncoding(from: FormatSettings(defaultEncodingForNewDocuments: "utf-16"))
        #expect(resolved == FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian))
    }

    @Test func defaultEncodingMapsUTF8ToTheDocumentedDefault() {
        let resolved = WindowCoordinator.defaultEncoding(from: FormatSettings(defaultEncodingForNewDocuments: "utf-8"))
        #expect(resolved == .utf8Default)
    }

    @Test func defaultEncodingFallsBackToUTF8ForAnUnrecognisedValue() {
        let resolved = WindowCoordinator.defaultEncoding(
            from: FormatSettings(defaultEncodingForNewDocuments: "shift-jis")
        )
        #expect(resolved == .utf8Default)
    }
}
