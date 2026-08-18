import Foundation
import Themes

/// Turns the active `Theme` into the CSS variable block used by the bundled
/// structural stylesheet.
///
/// Theme reuse is deliberate: every export theme shares the one structural
/// stylesheet (`Resources/structural.css`) and differs only by the `--md-*`
/// custom properties emitted here. There is no per-theme CSS copy and no
/// separate export palette.
public enum ExportThemeStylesheet {
    /// The `:root { … }` variable block derived from `theme.chrome`.
    public static func variables(for theme: Theme) -> String {
        let background = css(theme.chrome.background)
        let foreground = css(theme.chrome.foreground)
        let heading = headingColor(for: theme)
        let link = linkColor(for: theme)
        let muted = mutedColor(for: theme, foreground: theme.chrome.foreground)
        let rule = ruleColor(for: theme)
        let codeBackground = codeBackgroundColor(for: theme)

        return """
        :root {
          color-scheme: \(theme.appearance == .dark ? "dark" : "light");
          --md-background: \(background);
          --md-foreground: \(foreground);
          --md-heading: \(heading);
          --md-link: \(link);
          --md-muted: \(muted);
          --md-rule: \(rule);
          --md-code-bg: \(codeBackground);
        }
        """
    }

    /// Loads the single bundled structural stylesheet.
    public static var structural: String {
        guard let url = Bundle.module.url(forResource: "structural", withExtension: "css"),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Bundled structural stylesheet is missing; falling back to empty CSS.")
            return ""
        }
        return data
    }

    // MARK: - Colour derivation

    private static func headingColor(for theme: Theme) -> String {
        if let style = theme.style(for: "markup.heading") {
            return css(style.color)
        }
        return css(theme.chrome.foreground)
    }

    private static func linkColor(for theme: Theme) -> String {
        if let style = theme.style(for: "markup.link") {
            return css(style.color)
        }
        return css(theme.chrome.foreground)
    }

    private static func mutedColor(for theme: Theme, foreground: ThemeColor) -> String {
        // A readable secondary colour: blend the foreground toward the
        // background by ~40%, matching the "muted" feel of legacy previews.
        let blend = 0.4
        return css(ThemeColor(
            red: foreground.red * (1 - blend) + theme.chrome.background.red * blend,
            green: foreground.green * (1 - blend) + theme.chrome.background.green * blend,
            blue: foreground.blue * (1 - blend) + theme.chrome.background.blue * blend,
            alpha: foreground.alpha
        ))
    }

    private static func ruleColor(for theme: Theme) -> String {
        // A hairline derived from the foreground, low opacity.
        let blend = 0.12
        return css(ThemeColor(
            red: theme.chrome.foreground.red * (1 - blend) + theme.chrome.background.red * blend,
            green: theme.chrome.foreground.green * (1 - blend) + theme.chrome.background.green * blend,
            blue: theme.chrome.foreground.blue * (1 - blend) + theme.chrome.background.blue * blend,
            alpha: 1
        ))
    }

    private static func codeBackgroundColor(for theme: Theme) -> String {
        if let style = theme.style(for: "markup.raw") {
            // Use the raw markup colour at low opacity as the code backdrop.
            let blend = 0.08
            return css(ThemeColor(
                red: style.color.red * (1 - blend) + theme.chrome.background.red * blend,
                green: style.color.green * (1 - blend) + theme.chrome.background.green * blend,
                blue: style.color.blue * (1 - blend) + theme.chrome.background.blue * blend,
                alpha: 1
            ))
        }
        let blend = 0.06
        return css(ThemeColor(
            red: theme.chrome.foreground.red * (1 - blend) + theme.chrome.background.red * blend,
            green: theme.chrome.foreground.green * (1 - blend) + theme.chrome.background.green * blend,
            blue: theme.chrome.foreground.blue * (1 - blend) + theme.chrome.background.blue * blend,
            alpha: 1
        ))
    }

    private static func css(_ color: ThemeColor) -> String {
        let red = Int((color.red * 255).rounded())
        let green = Int((color.green * 255).rounded())
        let blue = Int((color.blue * 255).rounded())
        if color.alpha >= 0.999 {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
        return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, color.alpha)
    }
}
