import Foundation
import Observation

/// Single source of truth for the active theme. App-wide (one instance).
@MainActor
@Observable
public final class ThemeController {
    public private(set) var light: Theme
    public private(set) var dark: Theme
    public private(set) var appearance: ThemeAppearance
    public private(set) var current: Theme

    private let availableThemes: [Theme]
    private let preferenceStore: ThemePreferenceStoring

    public init(
        available: [Theme] = BundledThemes.all,
        preferenceStore: ThemePreferenceStoring = UserDefaultsThemePreferenceStore(),
        appearance: ThemeAppearance = .light
    ) {
        availableThemes = available
        self.preferenceStore = preferenceStore
        self.appearance = appearance

        guard let fallbackTheme = available.first else {
            fatalError("ThemeController requires at least one available theme")
        }
        let defaultLight = available.first { $0.appearance == .light } ?? fallbackTheme
        let defaultDark = available.first { $0.appearance == .dark } ?? fallbackTheme

        let initialLight: Theme
        let initialDark: Theme
        if let selection = preferenceStore.loadSelection() {
            initialLight = available.first { $0.id == selection.lightID } ?? defaultLight
            initialDark = available.first { $0.id == selection.darkID } ?? defaultDark
        } else {
            initialLight = defaultLight
            initialDark = defaultDark
        }

        light = initialLight
        dark = initialDark
        current = appearance == .dark ? initialDark : initialLight
    }

    public var available: [Theme] {
        availableThemes
    }

    /// Fed by the app from `NSApp.effectiveAppearance` changes.
    public func setAppearance(_ appearance: ThemeAppearance) {
        self.appearance = appearance
        current = appearance == .dark ? dark : light
    }

    /// Select a theme for its appearance slot.
    ///
    /// If the theme matches the current system appearance, it becomes
    /// `current` immediately. Otherwise the slot is saved so that future
    /// `setAppearance` calls use the user's choice for that appearance.
    public func select(_ theme: Theme) {
        if theme.appearance == .dark {
            dark = theme
        } else {
            light = theme
        }
        if theme.appearance == appearance {
            current = theme
        }
        preferenceStore.saveSelection(lightID: light.id, darkID: dark.id)
    }

    public func selectLight(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id && $0.appearance == .light }) else { return }
        light = theme
        preferenceStore.saveSelection(lightID: light.id, darkID: dark.id)
    }

    public func selectDark(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id && $0.appearance == .dark }) else { return }
        dark = theme
        preferenceStore.saveSelection(lightID: light.id, darkID: dark.id)
    }
}
