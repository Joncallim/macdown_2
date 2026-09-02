import Foundation
import Observation

/// Single source of truth for user settings. App-wide (one instance),
/// constructed by `AppDelegate` and reached everywhere else through
/// SwiftUI's environment — mirrors `Themes.ThemeController` and
/// `FileTree.FileTreePreferences`.
///
/// Every write goes straight to the backing store; there is no pending or
/// staged state and no explicit "Apply" action (epic-13-implementation.md
/// §7). Consumers read the published properties directly, so a change is
/// visible to every open tab/window the next time its SwiftUI body
/// re-evaluates — no manual notification is needed.
@MainActor
@Observable
public final class AppSettingsModel {
    public var general: GeneralSettings {
        didSet { store.general = general }
    }

    public var editor: EditorSettings {
        didSet { store.editor = editor }
    }

    public var markdown: MarkdownSettings {
        didSet { store.markdown = markdown }
    }

    public var previewExport: PreviewExportSettings {
        didSet { store.previewExport = previewExport }
    }

    public var formats: FormatSettings {
        didSet { store.formats = formats }
    }

    private var store: any AppSettingsStoring

    public init(store: any AppSettingsStoring = UserDefaultsAppSettingsStore()) {
        self.store = store
        general = store.general
        editor = store.editor
        markdown = store.markdown
        previewExport = store.previewExport
        formats = store.formats
    }
}
