import Foundation
import Testing
@testable import Themes

final class FakeThemePreferenceStore: ThemePreferenceStoring, @unchecked Sendable {
    private var selection: (lightID: String, darkID: String)?
    private var writes = 0
    private let lock = NSLock()

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    func loadSelection() -> (lightID: String, darkID: String)? {
        lock.lock()
        defer { lock.unlock() }
        return selection
    }

    func saveSelection(lightID: String, darkID: String) {
        lock.lock()
        defer { lock.unlock() }
        selection = (lightID, darkID)
        writes += 1
    }
}

@MainActor
struct ThemeControllerTests {
    private let lightTheme = Theme(
        id: "a-light",
        name: "A Light",
        appearance: .light,
        chrome: EditorChrome(
            background: ThemeColor(red: 1, green: 1, blue: 1),
            foreground: ThemeColor(red: 0, green: 0, blue: 0),
            caret: ThemeColor(red: 0, green: 0, blue: 0),
            selection: ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
        ),
        tokenStyles: [:]
    )

    private let darkTheme = Theme(
        id: "a-dark",
        name: "A Dark",
        appearance: .dark,
        chrome: EditorChrome(
            background: ThemeColor(red: 0, green: 0, blue: 0),
            foreground: ThemeColor(red: 1, green: 1, blue: 1),
            caret: ThemeColor(red: 1, green: 1, blue: 1),
            selection: ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
        ),
        tokenStyles: [:]
    )

    @Test func currentFollowsAppearance() {
        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: FakeThemePreferenceStore(),
            appearance: .light
        )
        #expect(controller.current.id == lightTheme.id)

        controller.setAppearance(.dark)
        #expect(controller.current.id == darkTheme.id)
    }

    @Test func selectThemePersists() {
        let store = FakeThemePreferenceStore()
        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: store,
            appearance: .light
        )

        controller.select(lightTheme)
        let selection = store.loadSelection()
        #expect(selection?.lightID == lightTheme.id)
    }

    @Test func selectThemeOfMatchingAppearanceBecomesCurrent() {
        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: FakeThemePreferenceStore(),
            appearance: .dark
        )

        controller.select(darkTheme)
        #expect(controller.current.id == darkTheme.id)
    }

    @Test func selectThemeOfOppositeAppearanceDoesNotChangeCurrent() {
        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: FakeThemePreferenceStore(),
            appearance: .dark
        )

        controller.select(lightTheme)
        #expect(controller.current.id == darkTheme.id)
        #expect(controller.light.id == lightTheme.id)
    }

    @Test func restoresPreviousSelection() {
        let store = FakeThemePreferenceStore()
        store.saveSelection(lightID: lightTheme.id, darkID: darkTheme.id)

        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: store,
            appearance: .dark
        )
        #expect(controller.current.id == darkTheme.id)
    }

    @Test func fallsBackWhenSelectionUnknown() {
        let store = FakeThemePreferenceStore()
        store.saveSelection(lightID: "missing", darkID: darkTheme.id)

        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: store,
            appearance: .light
        )
        #expect(controller.light.id == lightTheme.id)
    }

    @Test func crossedSavedIDsRestoreMatchingAppearancesWithoutRewritingPreferences() {
        let store = FakeThemePreferenceStore()
        store.saveSelection(lightID: darkTheme.id, darkID: lightTheme.id)

        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: store,
            appearance: .light
        )
        #expect(controller.light.id == lightTheme.id)
        #expect(controller.dark.id == darkTheme.id)
        #expect(controller.current.id == lightTheme.id)

        controller.setAppearance(.dark)
        #expect(controller.current.id == darkTheme.id)
        #expect(store.saveCount == 1)
        #expect(store.loadSelection()?.lightID == darkTheme.id)
        #expect(store.loadSelection()?.darkID == lightTheme.id)
    }

    @Test func unknownSavedIDsFallBackWithoutRewritingPreferences() {
        let store = FakeThemePreferenceStore()
        store.saveSelection(lightID: "missing-light", darkID: "missing-dark")

        let controller = ThemeController(
            available: [lightTheme, darkTheme],
            preferenceStore: store,
            appearance: .dark
        )
        #expect(controller.current.id == darkTheme.id)
        controller.setAppearance(.light)
        #expect(controller.current.id == lightTheme.id)
        #expect(store.saveCount == 1)
        #expect(store.loadSelection()?.lightID == "missing-light")
        #expect(store.loadSelection()?.darkID == "missing-dark")
    }

    @Test func missingAppearanceInInjectedCatalogUsesMatchingBundledFallback() {
        let lightOnly = ThemeController(
            available: [lightTheme],
            preferenceStore: FakeThemePreferenceStore(),
            appearance: .dark
        )
        #expect(lightOnly.dark.id == BundledThemes.dark.id)
        #expect(lightOnly.current.appearance == .dark)

        let darkOnly = ThemeController(
            available: [darkTheme],
            preferenceStore: FakeThemePreferenceStore(),
            appearance: .light
        )
        #expect(darkOnly.light.id == BundledThemes.light.id)
        #expect(darkOnly.current.appearance == .light)
    }

    @Test func emptyInjectedCatalogStillHasMatchingBundledFallbacks() {
        let controller = ThemeController(available: [], preferenceStore: FakeThemePreferenceStore())
        #expect(controller.light.id == BundledThemes.light.id)
        #expect(controller.dark.id == BundledThemes.dark.id)
    }
}
