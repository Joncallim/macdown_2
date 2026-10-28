@testable import AppSettings
import Foundation
import Testing

@MainActor
struct SettingsNestedCompatibilityTests {
    private static let editorKey = "appSettings.editor"

    private func isolated(_ body: (UserDefaults, UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let suite = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("no suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, UserDefaultsAppSettingsStore(defaults: defaults))
    }

    @Test func anUnknownNestedFontFieldIsProtectedFromAnOrdinaryEditorSave() throws {
        try isolated { defaults, store in
            var store = store
            let encoded = try JSONEncoder().encode(EditorSettings(indentationWidth: 2))
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
                  var font = object["font"] as? [String: Any]
            else {
                Issue.record("could not construct nested-font fixture")
                return
            }
            font["futureFontMember"] = true
            object["font"] = font
            let original = try JSONSerialization.data(withJSONObject: object)
            defaults.set(original, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = EditorSettings(indentationWidth: 3)

            #expect(defaults.data(forKey: Self.editorKey) == original)
            let reopened = UserDefaultsAppSettingsStore(defaults: defaults)
            #expect(reopened.editor == .default)
            #expect(reopened.unreadableDomains == [Self.editorKey])
        }
    }
}
