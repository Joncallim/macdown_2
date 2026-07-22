import Foundation

/// Loads the shipped themes from `Bundle.module`.
public enum BundledThemes {
    public static let light: Theme = load("Tomorrow Light")
    public static let dark: Theme = load("Tomorrow Dark")
    public static let all: [Theme] = [light, dark]

    static func load(_ resource: String) -> Theme {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let theme = try? JSONDecoder().decode(Theme.self, from: data)
        else {
            assertionFailure("Bundled theme \(resource).json is missing or corrupt; falling back to a minimal theme.")
            return minimalTheme(id: resource)
        }
        return theme
    }

    private static func minimalTheme(id: String) -> Theme {
        Theme(
            id: id,
            name: id,
            appearance: id.contains("dark") ? .dark : .light,
            chrome: EditorChrome(
                background: ThemeColor(red: 1, green: 1, blue: 1),
                foreground: ThemeColor(red: 0, green: 0, blue: 0),
                caret: ThemeColor(red: 0, green: 0, blue: 0),
                selection: ThemeColor(red: 0.7, green: 0.8, blue: 1)
            ),
            tokenStyles: [:]
        )
    }
}
