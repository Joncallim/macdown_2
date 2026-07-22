import Foundation
import Testing
@testable import Themes

final class FakeThemePreferenceStore: ThemePreferenceStoring, @unchecked Sendable {
    private var selection: (lightID: String, darkID: String)?
    private let lock = NSLock()

    func loadSelection() -> (lightID: String, darkID: String)? {
        lock.lock()
        defer { lock.unlock() }
        return selection
    }

    func saveSelection(lightID: String, darkID: String) {
        lock.lock()
        defer { lock.unlock() }
        selection = (lightID, darkID)
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
}
