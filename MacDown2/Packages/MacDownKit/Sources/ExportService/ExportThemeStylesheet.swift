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
        """
        :root {
          color-scheme: \(theme.appearance == .dark ? "dark" : "light");
          --md-background: \(css(theme.chrome.background));
          --md-foreground: \(css(theme.chrome.foreground));
          --md-heading: \(headingColor(for: theme));
          --md-link: \(linkColor(for: theme));
          --md-muted: \(mutedColor(for: theme));
          --md-rule: \(ruleColor(for: theme));
          --md-code-bg: \(codeBackgroundColor(for: theme));
        }
        """
    }

    /// The single bundled structural stylesheet, read once per process. Every
    /// export uses the same bytes, so re-reading the bundle per export would be
    /// pure filesystem work for an identical result.
    public static let structural: String = {
        guard let url = Bundle.module.url(forResource: "structural", withExtension: "css"),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Bundled structural stylesheet is missing; falling back to empty CSS.")
            return ""
        }
        return data
    }()

    // MARK: - Colour derivation

    private static func headingColor(for theme: Theme) -> String {
        guard let style = theme.style(for: "markup.heading") else {
            return css(theme.chrome.foreground)
        }
        return css(style.color)
    }

    private static func linkColor(for theme: Theme) -> String {
        guard let style = theme.style(for: "markup.link") else {
            return css(theme.chrome.foreground)
        }
        return css(style.color)
    }

    /// A readable secondary colour: the foreground moved part-way to the
    /// background, matching the "muted" feel of legacy previews.
    private static func mutedColor(for theme: Theme) -> String {
        css(blend(theme.chrome.foreground, towardBackgroundOf: theme, by: 0.4))
    }

    /// A hairline: the foreground moved nearly all the way to the background, so
    /// heading underlines and `<hr>` read as a rule rather than a bar.
    private static func ruleColor(for theme: Theme) -> String {
        css(blend(theme.chrome.foreground, towardBackgroundOf: theme, by: 0.88, opaque: true))
    }

    /// A code backdrop: a faint tint of the theme's raw-markup colour over the
    /// page background. It must stay close to the background — a code block is
    /// a surface, not a highlight — so the tint is deliberately slight.
    private static func codeBackgroundColor(for theme: Theme) -> String {
        let source = theme.style(for: "markup.raw")?.color ?? theme.chrome.foreground
        return css(blend(source, towardBackgroundOf: theme, by: 0.92, opaque: true))
    }

    /// Moves `color` toward the theme background. `amount` is how far it travels:
    /// `0` leaves it untouched, `1` reaches the background exactly.
    private static func blend(
        _ color: ThemeColor,
        towardBackgroundOf theme: Theme,
        by amount: Double,
        opaque: Bool = false
    ) -> ThemeColor {
        let background = theme.chrome.background
        let weight = min(max(amount, 0), 1)
        return ThemeColor(
            red: color.red * (1 - weight) + background.red * weight,
            green: color.green * (1 - weight) + background.green * weight,
            blue: color.blue * (1 - weight) + background.blue * weight,
            alpha: opaque ? 1 : color.alpha
        )
    }

    private static func css(_ color: ThemeColor) -> String {
        let red = channel(color.red)
        let green = channel(color.green)
        let blue = channel(color.blue)
        if color.alpha >= 0.999 {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
        return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, min(max(color.alpha, 0), 1))
    }

    /// A theme colour is nominally 0…1, but a malformed theme must still produce
    /// parseable CSS rather than something like `#-1ff00`.
    private static func channel(_ value: Double) -> Int {
        min(max(Int((value * 255).rounded()), 0), 255)
    }
}
