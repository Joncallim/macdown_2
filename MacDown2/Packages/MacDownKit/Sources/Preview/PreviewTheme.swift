import Foundation
import Themes

/// Colors used to render the Markdown preview, derived from the active editor
/// theme and system appearance.
public struct PreviewTheme: Sendable, Equatable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var codeBackground: ThemeColor
    public var codeForeground: ThemeColor
    public var linkColor: ThemeColor
    public var quoteColor: ThemeColor
    public var separatorColor: ThemeColor

    public init(
        background: ThemeColor,
        foreground: ThemeColor,
        codeBackground: ThemeColor,
        codeForeground: ThemeColor,
        linkColor: ThemeColor,
        quoteColor: ThemeColor,
        separatorColor: ThemeColor
    ) {
        self.background = background
        self.foreground = foreground
        self.codeBackground = codeBackground
        self.codeForeground = codeForeground
        self.linkColor = linkColor
        self.quoteColor = quoteColor
        self.separatorColor = separatorColor
    }
}

public extension PreviewTheme {
    /// Derives a preview theme from an editor theme.
    ///
    /// The preview uses the editor chrome colours so the two panes feel
    /// cohesive, with small adjustments for block-level elements.
    init(theme: Theme) {
        let chrome = theme.chrome
        background = chrome.background
        foreground = chrome.foreground
        codeBackground = chrome.foreground.mixing(with: chrome.background, fraction: 0.1)
        codeForeground = chrome.foreground
        linkColor = PreviewTheme.linkColor(for: theme.appearance)
        quoteColor = chrome.foreground
        separatorColor = chrome.foreground.mixing(with: chrome.background, fraction: 0.25)
    }

    static func `default`(for appearance: ThemeAppearance) -> PreviewTheme {
        PreviewTheme(theme: appearance == .dark ? BundledThemes.dark : BundledThemes.light)
    }

    private static func linkColor(for appearance: ThemeAppearance) -> ThemeColor {
        appearance == .dark
            ? ThemeColor(red: 0.35, green: 0.65, blue: 1.0)
            : ThemeColor(red: 0.0, green: 0.4, blue: 0.9)
    }
}

private extension ThemeColor {
    /// Returns a colour blended toward `other` by `fraction`.
    func mixing(with other: ThemeColor, fraction: Double) -> ThemeColor {
        let mix = min(max(fraction, 0), 1)
        let inv = 1 - mix
        return ThemeColor(
            red: red * inv + other.red * mix,
            green: green * inv + other.green * mix,
            blue: blue * inv + other.blue * mix,
            alpha: alpha * inv + other.alpha * mix
        )
    }
}
