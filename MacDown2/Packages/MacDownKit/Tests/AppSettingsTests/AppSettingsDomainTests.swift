@testable import AppSettings
import Foundation
import Testing

@Suite("AppSettings domain types")
struct AppSettingsDomainTests {
    @Test func fontDescriptorRoundTripsThroughCodable() throws {
        let font = FontDescriptor(familyName: "Menlo", size: 13.5)
        let data = try JSONEncoder().encode(font)
        let decoded = try JSONDecoder().decode(FontDescriptor.self, from: data)
        #expect(decoded == font)
    }

    @Test func generalSettingsDefaultRestoresPreviousSession() {
        #expect(GeneralSettings.default.launchBehavior == .restorePreviousSession)
    }

    @Test func generalSettingsRoundTripsThroughCodable() throws {
        let settings = GeneralSettings(launchBehavior: .startWithNewDocument)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GeneralSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func editorSettingsDefaultMatchesEditorConfigurationDefault() {
        let settings = EditorSettings.default
        #expect(settings.font == .systemMonospacedDefault)
        #expect(settings.wrapsLines == true)
        #expect(settings.showsInvisibles == false)
        #expect(settings.indentationWidth == 4)
        #expect(settings.assistsEnabled == true)
    }

    @Test func editorSettingsClampsIndentationWidthBelowRange() {
        #expect(EditorSettings(indentationWidth: 0).indentationWidth == 1)
        #expect(EditorSettings(indentationWidth: -5).indentationWidth == 1)
    }

    @Test func editorSettingsClampsIndentationWidthAboveRange() {
        #expect(EditorSettings(indentationWidth: 99).indentationWidth == 8)
        #expect(EditorSettings(indentationWidth: Int.max).indentationWidth == 8)
    }

    @Test func editorSettingsRoundTripsThroughCodable() throws {
        let settings = EditorSettings(
            font: FontDescriptor(familyName: "Menlo", size: 14),
            wrapsLines: false,
            showsInvisibles: true,
            indentationWidth: 2,
            assistsEnabled: false,
            continuesMarkdownPrefixes: false,
            completesMatchingCharacters: false,
            convertsTabsToSpaces: false,
            smartHome: false,
            autoIncrementOrderedLists: false
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func markdownSettingsDefaultParsesBlockDirectives() {
        #expect(MarkdownSettings.default.parsesBlockDirectives == true)
    }

    @Test func markdownSettingsRoundTripsThroughCodable() throws {
        let settings = MarkdownSettings(parsesBlockDirectives: false)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MarkdownSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func previewExportSettingsDefaultMatchesCurrentHardCodedBehavior() {
        let settings = PreviewExportSettings.default
        #expect(settings.defaultPreviewLayout == .split)
        #expect(settings.defaultExportFormat == .standaloneHTML)
        #expect(settings.defaultExportStyle == .embedded)
    }

    @Test func previewExportSettingsRoundTripsThroughCodable() throws {
        let settings = PreviewExportSettings(
            defaultPreviewLayout: .previewOnly,
            defaultExportFormat: .pdf,
            defaultExportStyle: .linked
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PreviewExportSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func formatSettingsDefaultIsUTF8() {
        #expect(FormatSettings.default.defaultEncodingForNewDocuments == "utf-8")
    }

    @Test func formatSettingsRoundTripsThroughCodable() throws {
        let settings = FormatSettings(defaultEncodingForNewDocuments: "utf-16")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FormatSettings.self, from: data)
        #expect(decoded == settings)
    }
}
