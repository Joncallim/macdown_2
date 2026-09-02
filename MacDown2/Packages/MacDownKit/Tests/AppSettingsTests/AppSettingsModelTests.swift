@testable import AppSettings
import Foundation
import Testing

/// `AppSettingsStoring` is `@MainActor`, so (unlike `Themes`'
/// `FakeThemePreferenceStore`, whose protocol is not actor-isolated) this
/// fake needs no manual locking — MainActor isolation already serializes
/// every access.
@MainActor
private final class FakeAppSettingsStore: AppSettingsStoring {
    var general: GeneralSettings = .default
    var editor: EditorSettings = .default
    var markdown: MarkdownSettings = .default
    var previewExport: PreviewExportSettings = .default
    var formats: FormatSettings = .default
}

@MainActor
@Suite("AppSettingsModel")
struct AppSettingsModelTests {
    @Test func initReadsEveryDomainFromTheStore() {
        let store = FakeAppSettingsStore()
        store.editor = EditorSettings(indentationWidth: 2)
        store.markdown = MarkdownSettings(parsesBlockDirectives: false)

        let model = AppSettingsModel(store: store)
        #expect(model.editor.indentationWidth == 2)
        #expect(model.markdown.parsesBlockDirectives == false)
        #expect(model.general == .default)
    }

    @Test func settingEditorWritesThroughToTheStore() {
        let store = FakeAppSettingsStore()
        let model = AppSettingsModel(store: store)

        model.editor = EditorSettings(wrapsLines: false, indentationWidth: 8)

        #expect(store.editor.wrapsLines == false)
        #expect(store.editor.indentationWidth == 8)
    }

    @Test func settingOneDomainDoesNotWriteToAnother() {
        let store = FakeAppSettingsStore()
        let model = AppSettingsModel(store: store)

        model.previewExport = PreviewExportSettings(defaultExportFormat: .pdf)

        #expect(store.editor == .default)
        #expect(store.general == .default)
        #expect(store.markdown == .default)
        #expect(store.formats == .default)
    }

    @Test func aSecondModelOverTheSameStoreObservesThePriorWrite() {
        let store = FakeAppSettingsStore()
        let first = AppSettingsModel(store: store)
        first.formats = FormatSettings(defaultEncodingForNewDocuments: "utf-16")

        let second = AppSettingsModel(store: store)
        #expect(second.formats.defaultEncodingForNewDocuments == "utf-16")
    }
}
