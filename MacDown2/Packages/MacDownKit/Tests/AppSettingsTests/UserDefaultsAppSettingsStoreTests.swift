@testable import AppSettings
import Foundation
import Testing

@MainActor
@Suite("UserDefaultsAppSettingsStore")
struct UserDefaultsAppSettingsStoreTests {
    /// Every case below needs its own throwaway suite: unlike an in-process
    /// fake, `UserDefaults(suiteName:)` persists to disk, so sharing a suite
    /// across tests would let one test's writes leak into another's.
    private func withIsolatedStore(_ body: (UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }
        try body(UserDefaultsAppSettingsStore(defaults: defaults))
    }

    @Test func freshSuiteReturnsDocumentedDefaultsForEveryDomain() {
        withIsolatedStore { store in
            #expect(store.general == .default)
            #expect(store.editor == .default)
            #expect(store.markdown == .default)
            #expect(store.previewExport == .default)
            #expect(store.formats == .default)
        }
    }

    @Test func writingOneDomainPersistsAcrossANewStoreInstanceOverTheSameSuite() {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }

        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.editor = EditorSettings(indentationWidth: 2, assistsEnabled: false)

        let reloaded = UserDefaultsAppSettingsStore(defaults: defaults)
        #expect(reloaded.editor.indentationWidth == 2)
        #expect(reloaded.editor.assistsEnabled == false)
    }

    @Test func writingOneDomainDoesNotDisturbAnother() {
        withIsolatedStore { store in
            var store = store
            store.markdown = MarkdownSettings(parsesBlockDirectives: false)
            #expect(store.editor == .default)
            #expect(store.formats == .default)
        }
    }

    @Test func corruptedDataFallsBackToTheWholeDomainDefaultNotAPartialDecode() {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "appSettings.editor")

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        #expect(store.editor == .default)
    }

    @Test func mismatchedShapeFallsBackToTheWholeDomainDefault() throws {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }
        // Valid JSON, but not the shape EditorSettings expects.
        let unrelatedShape = try JSONEncoder().encode(["not": "editor settings"])
        defaults.set(unrelatedShape, forKey: "appSettings.editor")

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        #expect(store.editor == .default)
    }

    @Test func nonDataValueStoredUnderAKeyFallsBackToDefault() {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }
        defaults.set("not JSON data at all", forKey: "appSettings.formats")

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        #expect(store.formats == .default)
    }
}
