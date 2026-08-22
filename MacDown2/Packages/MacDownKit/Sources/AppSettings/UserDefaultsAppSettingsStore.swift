import Foundation

/// `UserDefaults`-backed `AppSettingsStoring`. Each domain is one JSON blob
/// under one key, matching `WorkspaceStateStore.sidebarSectionExpanded`'s
/// existing whole-struct-as-one-key convention.
///
/// Accepts an injectable `UserDefaults` instance so callers can isolate
/// storage — production code passes the app's UI-testing-isolated suite the
/// same way `AppDelegate` already does for `FileTreePreferences` and
/// `WorkspaceStateStore`; tests pass a uniquely named suite.
@MainActor
public struct UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var general: GeneralSettings {
        get { load(.general) }
        set { save(newValue, key: .general) }
    }

    public var editor: EditorSettings {
        get { load(.editor) }
        set { save(newValue, key: .editor) }
    }

    public var markdown: MarkdownSettings {
        get { load(.markdown) }
        set { save(newValue, key: .markdown) }
    }

    public var previewExport: PreviewExportSettings {
        get { load(.previewExport) }
        set { save(newValue, key: .previewExport) }
    }

    public var formats: FormatSettings {
        get { load(.formats) }
        set { save(newValue, key: .formats) }
    }

    /// Whole-domain fallback on any decode failure — a missing key, a type
    /// mismatch, or a shape a future/older app version doesn't recognize —
    /// never a partially-decoded value. See epic-13-implementation.md §9.
    private func load<T: AppSettingsDomain>(_ key: Key) -> T {
        guard let data = defaults.data(forKey: key.rawValue),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { return T.defaultValue }
        return value
    }

    private func save(_ value: some Encodable, key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    private enum Key: String {
        case general = "appSettings.general"
        case editor = "appSettings.editor"
        case markdown = "appSettings.markdown"
        case previewExport = "appSettings.previewExport"
        case formats = "appSettings.formats"
    }
}
