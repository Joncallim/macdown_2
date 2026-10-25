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
    /// Stored members this build can preserve when it writes the whole JSON
    /// domain. Unknown members are rejected before typed decoding so a later
    /// ordinary save cannot silently discard data from another schema.
    static var admittedTopLevelKeys: Set<String> { get }
}

extension GeneralSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }

    public static let admittedTopLevelKeys: Set<String> = ["launchBehavior"]
}

extension EditorSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }

    public static let admittedTopLevelKeys: Set<String> = [
        "font", "wrapsLines", "showsInvisibles", "showsStatusBar", "indentationWidth", "assistsEnabled",
        "continuesMarkdownPrefixes", "completesMatchingCharacters", "convertsTabsToSpaces", "smartHome",
        "autoIncrementOrderedLists",
    ]
}

extension MarkdownSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }

    public static let admittedTopLevelKeys: Set<String> = ["parsesBlockDirectives"]
}

extension PreviewExportSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }

    public static let admittedTopLevelKeys: Set<String> = [
        "defaultPreviewLayout", "defaultExportFormat", "defaultExportStyle",
    ]
}

extension FormatSettings: AppSettingsDomain {
    public static var defaultValue: Self {
        .default
    }

    public static let admittedTopLevelKeys: Set<String> = ["defaultEncodingForNewDocuments"]
}
