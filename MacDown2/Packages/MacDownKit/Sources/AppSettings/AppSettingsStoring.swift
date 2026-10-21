import Foundation

/// Storage seam for the five settings domains. Mirrors
/// `Themes.ThemePreferenceStoring` and `FileTree.FileTreePreferenceStoring`:
/// a narrow protocol so `AppSettingsModel` can be tested against an
/// in-memory fake without touching real `UserDefaults`.
@MainActor
public protocol AppSettingsStoring: Sendable {
    var general: GeneralSettings { get set }
    var editor: EditorSettings { get set }
    var markdown: MarkdownSettings { get set }
    var previewExport: PreviewExportSettings { get set }
    var formats: FormatSettings { get set }
    /// Present domains this build cannot read or safely replace. Changes to these domains
    /// may apply to the session model, but must not overwrite their persisted originals.
    var unreadableDomains: [String] { get }
}

public extension AppSettingsStoring {
    var unreadableDomains: [String] {
        []
    }
}

/// Domain types that know their own default, so `UserDefaultsAppSettingsStore`
/// can decode-or-fall-back generically instead of repeating the same logic
/// five times.
public protocol AppSettingsDomain: Codable, Equatable {
    static var defaultValue: Self { get }
}

extension GeneralSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }
}

extension EditorSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }
}

extension MarkdownSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }
}

extension PreviewExportSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }
}

extension FormatSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }
}
