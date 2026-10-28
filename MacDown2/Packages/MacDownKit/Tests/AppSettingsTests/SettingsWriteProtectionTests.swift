@testable import AppSettings
import Foundation
import Testing

@MainActor
struct SettingsWriteProtectionTests {
    private nonisolated static let keys = [
        "appSettings.general", "appSettings.editor", "appSettings.markdown",
        "appSettings.previewExport", "appSettings.formats",
    ]

    enum UnreadableValue: CaseIterable, Sendable {
        case future, malformed, string, dictionary

        var object: NSObject {
            switch self {
            case .future: Data("{\"schemaVersion\":2,\"futureField\":\"retain\"}".utf8) as NSData
            case .malformed: Data([0xFF, 0x00, 0x7B]) as NSData
            case .string: "unreadable string" as NSString
            case .dictionary: ["unknown": ["preserve", "everything"]] as NSDictionary
            }
        }
    }

    private func isolated(_ body: (UserDefaults, inout UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let name = "settings-write-protection-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("could not create isolated settings suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        try body(defaults, &store)
    }

    private func writeDefault(_ key: String, to store: inout UserDefaultsAppSettingsStore) {
        switch key {
        case "appSettings.general": store.general = .default
        case "appSettings.editor": store.editor = .default
        case "appSettings.markdown": store.markdown = .default
        case "appSettings.previewExport": store.previewExport = .default
        case "appSettings.formats": store.formats = .default
        default: Issue.record("unknown test domain")
        }
    }

    private func readableShapeWithUnknownMember(for key: String) -> Data {
        switch key {
        case "appSettings.general":
            return Data("{\"launchBehavior\":\"restorePreviousSession\",\"unknown\":true}".utf8)
        case "appSettings.editor":
            return Data((
                "{\"font\":{\"familyName\":\"Menlo\",\"size\":13},\"wrapsLines\":true,\"showsInvisibles\":false,"
                    + "\"showsStatusBar\":true,\"indentationWidth\":4,\"assistsEnabled\":true,"
                    + "\"continuesMarkdownPrefixes\":true,\"completesMatchingCharacters\":true,"
                    + "\"convertsTabsToSpaces\":true,\"smartHome\":true,\"autoIncrementOrderedLists\":true,"
                    + "\"unknown\":true}"
            ).utf8)
        case "appSettings.markdown":
            return Data("{\"parsesBlockDirectives\":false,\"unknown\":true}".utf8)
        case "appSettings.previewExport":
            return Data((
                "{\"defaultPreviewLayout\":\"split\",\"defaultExportFormat\":\"standaloneHTML\","
                    + "\"defaultExportStyle\":\"embedded\",\"unknown\":true}"
            ).utf8)
        case "appSettings.formats":
            return Data("{\"defaultEncodingForNewDocuments\":\"utf-8\",\"unknown\":true}".utf8)
        default:
            Issue.record("unknown test domain")
            return Data()
        }
    }

    @Test(arguments: keys, UnreadableValue.allCases)
    func everyUnreadablePrimarySurvivesOrdinarySaveAndRestart(key: String, value: UnreadableValue) {
        isolated { defaults, store in
            let original = value.object
            let backup = Data("earlier unreadable generation".utf8)
            defaults.set(original, forKey: key)
            defaults.set(backup, forKey: key + ".preservedUnreadable")
            #expect(store.unreadableDomains == [key])

            writeDefault(key, to: &store)

            #expect((defaults.object(forKey: key) as? NSObject)?.isEqual(original) == true)
            #expect(store.unreadableDomains == [key])
            #expect(store.preservedUnreadableData(forDomain: key) == backup)
            let reopened = UserDefaultsAppSettingsStore(defaults: defaults)
            #expect(reopened.unreadableDomains == [key])
        }
    }

    @Test(arguments: keys)
    func anUnknownTopLevelMemberProtectsEveryWholeDomain(key: String) {
        isolated { defaults, store in
            let original = readableShapeWithUnknownMember(for: key)
            defaults.set(original, forKey: key)

            #expect(store.unreadableDomains == [key])
            writeDefault(key, to: &store)

            #expect(defaults.data(forKey: key) == original)
            #expect(UserDefaultsAppSettingsStore(defaults: defaults).unreadableDomains == [key])
        }
    }

    @Test func successiveUnreadableGenerationsRemainAtThePrimaryKey() {
        isolated { defaults, store in
            let key = "appSettings.editor"
            let first = Data("first invalid bytes".utf8)
            let second = Data("second invalid bytes".utf8)
            for original in [first, second] {
                defaults.set(original, forKey: key)
                store.editor = EditorSettings(indentationWidth: 3)
                #expect(defaults.data(forKey: key) == original)
                #expect(store.unreadableDomains == [key])
            }
            #expect(store.preservedUnreadableData(forDomain: key) == first)
        }
    }

    @Test func aModelCannotOverwriteNewUnreadableDataAfterItsEarlierSuccessfulLoad() {
        isolated { defaults, store in
            store.editor = EditorSettings(indentationWidth: 2)
            let model = AppSettingsModel(store: store)
            let original = UnreadableValue.future.object
            defaults.set(original, forKey: "appSettings.editor")

            model.editor.indentationWidth = 6

            #expect(model.editor.indentationWidth == 6, "the live session still applies the edit")
            #expect(model.hasUnreadableSettings)
            #expect((defaults.object(forKey: "appSettings.editor") as? NSObject)?.isEqual(original) == true)
            #expect(store.unreadableDomains == ["appSettings.editor"])
            let restarted = AppSettingsModel(store: store)
            #expect(restarted.editor == .default)
            #expect(restarted.hasUnreadableSettings)
        }
    }

    @Test func absentAndReadableDomainsPersistWhileAnotherDomainIsProtected() {
        isolated { defaults, store in
            for key in Self.keys {
                writeDefault(key, to: &store)
                #expect(defaults.data(forKey: key) != nil)
            }
            #expect(store.unreadableDomains.isEmpty)
            #expect(!AppSettingsModel(store: store).hasUnreadableSettings)
            let original = UnreadableValue.dictionary.object
            defaults.set(original, forKey: "appSettings.editor")
            store.markdown = MarkdownSettings(parsesBlockDirectives: true)
            #expect(UserDefaultsAppSettingsStore(defaults: defaults).markdown.parsesBlockDirectives)
            #expect((defaults.object(forKey: "appSettings.editor") as? NSObject)?.isEqual(original) == true)
            defaults.removeObject(forKey: "appSettings.editor")
            store.editor = EditorSettings(indentationWidth: 5)
            #expect(UserDefaultsAppSettingsStore(defaults: defaults).editor.indentationWidth == 5)
            #expect(store.unreadableDomains.isEmpty)
            #expect(!AppSettingsModel(store: store).hasUnreadableSettings)
        }
    }

    @Test func aReadableReplacementMakesTheDomainWritableAgain() throws {
        try isolated { defaults, store in
            defaults.set(UnreadableValue.future.object, forKey: "appSettings.editor")
            let model = AppSettingsModel(store: store)
            #expect(model.hasUnreadableSettings)
            try defaults.set(JSONEncoder().encode(EditorSettings(indentationWidth: 2)), forKey: "appSettings.editor")

            model.editor.indentationWidth = 7

            #expect(!model.hasUnreadableSettings)
            #expect(UserDefaultsAppSettingsStore(defaults: defaults).editor.indentationWidth == 7)
        }
    }
}
