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

    /// Absent data is the default. Present data is decoded through each domain's compatible `Decodable` (older
    /// schema-less blobs keep every valid value; see `EditorSettings.init(from:)`). Data that cannot be understood
    /// (malformed bytes, a wrong type, an out-of-range value, a newer `schemaVersion`) falls back to the default
    /// for the running session only: the raw bytes stay in `UserDefaults`, are reported by `unreadableDomains`, and
    /// are copied to a one-time preserved key before any later `save` could replace them (#53).
    private func load<T: AppSettingsDomain>(_ key: Key) -> T {
        guard let data = defaults.data(forKey: key.rawValue), let value = Self.decode(T.self, from: data)
        else { return T.defaultValue }
        return value
    }

    private func save(_ value: some Encodable, key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        preserveUnreadableBytes(for: key, ifDifferentFrom: data)
        defaults.set(data, forKey: key.rawValue)
    }

    /// The highest settings schema this build understands. The historical schema has no version key (named
    /// "schema-less"); a blob that declares a larger `schemaVersion` was written by a newer build and must not be
    /// rewritten by this one.
    nonisolated static let supportedSchemaVersion = 1

    fileprivate nonisolated static func decode<T: Decodable>(_: T.Type, from data: Data) -> T? {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let declared = object["schemaVersion"] {
            guard let version = declared as? Int, version <= supportedSchemaVersion else { return nil }
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Domains whose stored bytes exist but cannot be read by this build; empty when everything is absent or valid.
    public var unreadableDomains: [String] {
        Key.allCases.compactMap { key in
            guard let data = defaults.data(forKey: key.rawValue) else { return nil }
            return key.decodes(data) ? nil : key.rawValue
        }
    }

    /// The first unreadable blob for `key`, kept verbatim (never overwritten once present).
    public func preservedUnreadableData(forDomain name: String) -> Data? {
        defaults.data(forKey: Self.preservedKey(for: name))
    }

    private static func preservedKey(for name: String) -> String {
        name + ".preservedUnreadable"
    }

    private func preserveUnreadableBytes(for key: Key, ifDifferentFrom replacement: Data) {
        guard let existing = defaults.data(forKey: key.rawValue), existing != replacement,
              !key.decodes(existing),
              defaults.data(forKey: Self.preservedKey(for: key.rawValue)) == nil
        else { return }
        defaults.set(existing, forKey: Self.preservedKey(for: key.rawValue))
    }

    private enum Key: String, CaseIterable {
        case general = "appSettings.general"
        case editor = "appSettings.editor"
        case markdown = "appSettings.markdown"
        case previewExport = "appSettings.previewExport"
        case formats = "appSettings.formats"

        func decodes(_ data: Data) -> Bool {
            switch self {
            case .general: UserDefaultsAppSettingsStore.decode(GeneralSettings.self, from: data) != nil
            case .editor: UserDefaultsAppSettingsStore.decode(EditorSettings.self, from: data) != nil
            case .markdown: UserDefaultsAppSettingsStore.decode(MarkdownSettings.self, from: data) != nil
            case .previewExport: UserDefaultsAppSettingsStore.decode(PreviewExportSettings.self, from: data) != nil
            case .formats: UserDefaultsAppSettingsStore.decode(FormatSettings.self, from: data) != nil
            }
        }
    }
}
