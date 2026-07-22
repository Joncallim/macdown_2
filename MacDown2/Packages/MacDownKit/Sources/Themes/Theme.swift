import Foundation

/// A complete theme. `tokenStyles` is keyed by canonical capture name.
///
/// Lookup must go through `style(for:)`, which applies the fallback chain — do
/// not index `tokenStyles` directly.
public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var appearance: ThemeAppearance
    public var chrome: EditorChrome
    public var tokenStyles: [String: TokenStyle]

    public init(
        id: String,
        name: String,
        appearance: ThemeAppearance,
        chrome: EditorChrome,
        tokenStyles: [String: TokenStyle]
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.chrome = chrome
        self.tokenStyles = tokenStyles
    }

    /// Resolve a capture name to a style using the fallback chain:
    /// `"keyword.control"` → `"keyword.control"` → `"keyword"` → `nil`.
    /// `nil` means the caller should use `chrome.foreground`.
    public func style(for captureName: String) -> TokenStyle? {
        var current: String? = captureName

        while let key = current {
            if let style = tokenStyles[key] {
                return style
            }
            current = Self.fallback(key)
        }

        return nil
    }

    private static func fallback(_ name: String) -> String? {
        guard let lastDot = name.lastIndex(of: ".") else { return nil }
        return String(name[..<lastDot])
    }
}
