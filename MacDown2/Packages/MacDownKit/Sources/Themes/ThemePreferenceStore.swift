import Foundation

/// Persists which light/dark theme the user picked.
public protocol ThemePreferenceStoring: Sendable {
    func loadSelection() -> (lightID: String, darkID: String)?
    func saveSelection(lightID: String, darkID: String)
}

/// `UserDefaults`-backed preference store. Uses an optional suite name so tests
/// can isolate writes to a temp-directory suite.
public struct UserDefaultsThemePreferenceStore: ThemePreferenceStoring {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func loadSelection() -> (lightID: String, darkID: String)? {
        guard let defaults = userDefaults else { return nil }
        guard let light = defaults.string(forKey: Keys.light),
              let dark = defaults.string(forKey: Keys.dark) else { return nil }
        return (light, dark)
    }

    public func saveSelection(lightID: String, darkID: String) {
        guard let defaults = userDefaults else { return }
        defaults.set(lightID, forKey: Keys.light)
        defaults.set(darkID, forKey: Keys.dark)
    }

    private var userDefaults: UserDefaults? {
        if let suiteName {
            return UserDefaults(suiteName: suiteName)
        }
        return .standard
    }

    private enum Keys {
        static let light = "MacDown2ThemeLight"
        static let dark = "MacDown2ThemeDark"
    }
}
