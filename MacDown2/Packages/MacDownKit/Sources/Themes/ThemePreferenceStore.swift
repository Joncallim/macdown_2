import Foundation

/// Persists which light/dark theme the user picked.
public protocol ThemePreferenceStoring: Sendable {
    func loadSelection() -> (lightID: String, darkID: String)?
    func saveSelection(lightID: String, darkID: String)
    func loadAppearanceMode() -> ThemeAppearanceMode?
    func saveAppearanceMode(_ mode: ThemeAppearanceMode)
}

/// `UserDefaults`-backed preference store. Uses an optional suite name so tests
/// can isolate writes to a temp-directory suite.
public struct UserDefaultsThemePreferenceStore: ThemePreferenceStoring {
    private let defaults: UserDefaultsBox?

    public init(suiteName: String? = nil) {
        if let suiteName {
            defaults = UserDefaults(suiteName: suiteName).map(UserDefaultsBox.init)
        } else {
            defaults = UserDefaultsBox(.standard)
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = UserDefaultsBox(defaults)
    }

    public func loadSelection() -> (lightID: String, darkID: String)? {
        guard let defaults,
              let light = defaults.value.string(forKey: Keys.light),
              let dark = defaults.value.string(forKey: Keys.dark) else { return nil }
        return (light, dark)
    }

    public func saveSelection(lightID: String, darkID: String) {
        defaults?.value.set(lightID, forKey: Keys.light)
        defaults?.value.set(darkID, forKey: Keys.dark)
    }

    public func loadAppearanceMode() -> ThemeAppearanceMode? {
        guard let rawValue = defaults?.value.string(forKey: Keys.appearanceMode) else { return nil }
        return ThemeAppearanceMode(rawValue: rawValue)
    }

    public func saveAppearanceMode(_ mode: ThemeAppearanceMode) {
        defaults?.value.set(mode.rawValue, forKey: Keys.appearanceMode)
    }

    private enum Keys {
        static let light = "MacDown2ThemeLight"
        static let dark = "MacDown2ThemeDark"
        static let appearanceMode = "MacDown2ThemeAppearanceMode"
    }
}

/// `UserDefaults` is safe for concurrent use but is not annotated Sendable by
/// Foundation. The preference-store protocol deliberately exposes only its
/// synchronous key-value operations.
private final class UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
