import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Highlighting
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes
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

    @Test func markdownParseOptionsDefaultsToOnWhenSettingsUnavailable() {
        #expect(!DocumentEditorSplitView.markdownParseOptions(from: nil).blockDirectives)
    }

    // MARK: - Editor assists

    @Test func assistConfigurationReflectsEveryFieldForMarkdown() {
        let settings = EditorSettings(
            indentationWidth: 2,
            assistsEnabled: false,
            continuesMarkdownPrefixes: false,
            completesMatchingCharacters: false,
            convertsTabsToSpaces: false,
            smartHome: false,
            autoIncrementOrderedLists: false
        )
        let config = DocumentEditorSplitView.assistConfiguration(from: settings, isMarkdown: true)
        #expect(!config.isEnabled)
        #expect(!config.continuesMarkdownPrefixes)
        #expect(!config.completesMatchingCharacters)
        #expect(!config.completesMarkdownDelimiters)
        #expect(!config.convertsTabsToSpaces)
        #expect(!config.smartHome)
        #expect(!config.autoIncrementOrderedLists)
        #expect(config.indentationWidth == 2)
    }

    /// EPIC-22 §6.11, Slice 4a: for a non-Markdown format, the Markdown-only
    /// fields are forced off regardless of the user's own setting, while the
    /// general mechanics still respect it.
    @Test func assistConfigurationForcesMarkdownOnlyFieldsOffForOtherFormats() {
        let settings = EditorSettings(
            indentationWidth: 2,
            assistsEnabled: true,
            continuesMarkdownPrefixes: true,
            completesMatchingCharacters: true,
            convertsTabsToSpaces: true,
            smartHome: true,
            autoIncrementOrderedLists: true
        )
        let config = DocumentEditorSplitView.assistConfiguration(from: settings, isMarkdown: false)
        #expect(config.isEnabled)
        #expect(!config.continuesMarkdownPrefixes)
        #expect(config.completesMatchingCharacters)
        #expect(!config.completesMarkdownDelimiters)
        #expect(config.convertsTabsToSpaces)
        #expect(config.smartHome)
        #expect(!config.autoIncrementOrderedLists)
    }

    @Test func assistConfigurationFallsBackToMarkdownDefaultWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.assistConfiguration(from: nil, isMarkdown: true) == .markdownDefault)
    }

    @Test func assistConfigurationFallsBackToGeneralWhenSettingsUnavailableForOtherFormats() {
        #expect(DocumentEditorSplitView.assistConfiguration(from: nil, isMarkdown: false) == .general)
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

extension AppSettingsWiringTests {
    @Test("document windows use saved font settings and follow later changes")
    func documentWindowsShareTheLiveFontSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "document-font-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let settings = AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults))
        settings.editor.font = FontDescriptor(familyName: "Helvetica", size: 19)
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json")),
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery")),
            themeController: ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: defaults)),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        defer {
            for controller in coordinator.controllers {
                coordinator.removeController(controller)
                controller.close()
            }
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let first = try makeFontSettingsEditor(coordinator: coordinator)
        try #require(await editorUsesFont(first, descriptor: settings.editor.font))
        settings.editor.font = FontDescriptor(familyName: "Menlo", size: 24)
        #expect(await editorUsesFont(first, descriptor: settings.editor.font))
        let second = try makeFontSettingsEditor(coordinator: coordinator)
        #expect(await editorUsesFont(second, descriptor: settings.editor.font))
    }

    private func makeFontSettingsEditor(coordinator: WindowCoordinator) throws -> EditorTextSystem {
        let model = coordinator.makeWindowModel()
        let format = try #require(FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" })
        model.tabStore.newTab(document: FileDocument(
            text: "Document font settings must reach rendered text.",
            format: format,
            recoveryBuffer: coordinator.recoveryBuffer
        ))
        let tabID = try #require(model.tabStore.activeTab?.id)
        model.tabStore.setPreviewLayout(.editorOnly, for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers.append(controller)
        return try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
    }

    private func editorUsesFont(_ system: EditorTextSystem, descriptor: FontDescriptor) async -> Bool {
        let expected = DocumentEditorSplitView.resolvedFont(from: descriptor)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let rendered = system.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            if system.textView.font == expected, rendered == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
