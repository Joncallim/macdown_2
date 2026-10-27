import Foundation
import Observation

/// Single source of truth for the active theme. App-wide (one instance).
@MainActor
@Observable
public final class ThemeController {
    public private(set) var light: Theme
    public private(set) var dark: Theme
    public private(set) var systemAppearance: ThemeAppearance
    public private(set) var appearanceMode: ThemeAppearanceMode
    public private(set) var appearance: ThemeAppearance
    public private(set) var current: Theme

    /// AppKit owns the actual application appearance. The app assigns this
    /// callback after construction so Themes stays platform-neutral.
    public var appearanceModeDidChange: ((ThemeAppearanceMode) -> Void)?

    private let availableThemes: [Theme]
    private let preferenceStore: ThemePreferenceStoring

    public init(
        available: [Theme] = BundledThemes.all,
        preferenceStore: ThemePreferenceStoring = UserDefaultsThemePreferenceStore(),
        appearance: ThemeAppearance = .light
    ) {
        availableThemes = available
        self.preferenceStore = preferenceStore
        let initialAppearanceMode = preferenceStore.loadAppearanceMode() ?? .system
        systemAppearance = appearance
        appearanceMode = initialAppearanceMode
        let effectiveAppearance = initialAppearanceMode.resolvedAppearance(systemAppearance: appearance)
        self.appearance = effectiveAppearance

        let defaultLight = available.first { $0.appearance == .light } ?? BundledThemes.light
        let defaultDark = available.first { $0.appearance == .dark } ?? BundledThemes.dark

        let initialLight: Theme
        let initialDark: Theme
        if let selection = preferenceStore.loadSelection() {
            initialLight = available.first { $0.id == selection.lightID && $0.appearance == .light } ?? defaultLight
            initialDark = available.first { $0.id == selection.darkID && $0.appearance == .dark } ?? defaultDark
        } else {
            initialLight = defaultLight
            initialDark = defaultDark
        }

        light = initialLight
        dark = initialDark
        current = effectiveAppearance == .dark ? initialDark : initialLight
    }

    public var available: [Theme] {
        availableThemes
    }

    /// Fed by the app from macOS appearance changes.
    public func setAppearance(_ appearance: ThemeAppearance) {
        systemAppearance = appearance
        guard appearanceMode == .system else { return }
        apply(appearance)
    }

    /// Applies the app-wide choice without changing either saved theme slot.
    public func setAppearanceMode(_ mode: ThemeAppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        preferenceStore.saveAppearanceMode(mode)
        apply(mode.resolvedAppearance(systemAppearance: systemAppearance))
        appearanceModeDidChange?(mode)
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
        if appearance == .light {
            current = theme
        }
        preferenceStore.saveSelection(lightID: light.id, darkID: dark.id)
    }

    public func selectDark(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id && $0.appearance == .dark }) else { return }
        dark = theme
        if appearance == .dark {
            current = theme
        }
        preferenceStore.saveSelection(lightID: light.id, darkID: dark.id)
    }

    private func apply(_ appearance: ThemeAppearance) {
        self.appearance = appearance
        current = appearance == .dark ? dark : light
    }
}
