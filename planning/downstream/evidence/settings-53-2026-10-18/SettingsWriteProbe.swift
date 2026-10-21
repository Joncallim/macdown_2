import Foundation

/// Synthetic values and a uniquely named suite only; no default or legacy domain.
@main
struct SettingsWriteProbe {
    @MainActor
    static func main() throws {
        let suite = "app.mostlytext.settings-audit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No fixture suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        let key = "appSettings.editor"
        func future(_ marker: String) throws -> Data {
            let current = try JSONEncoder().encode(EditorSettings(indentationWidth: 2))
            var object = try JSONSerialization.jsonObject(with: current) as! [String: Any]
            object["schemaVersion"] = 2
            object["futureOnlyField"] = marker
            return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        }
        let first = try future("first synthetic generation")
        let second = try future("second synthetic generation")
        defaults.set(first, forKey: key)
        let firstReported = store.unreadableDomains == [key]
        _ = store.editor
        let firstUnchangedAfterLoad = defaults.data(forKey: key) == first
        store.editor = EditorSettings(indentationWidth: 5)
        let firstPrimaryReplaced = defaults.data(forKey: key) != first
        let firstBackupRetained = store.preservedUnreadableData(forDomain: key) == first

        defaults.set(second, forKey: key)
        store.editor = EditorSettings(indentationWidth: 6)
        let fixtureValues = defaults.persistentDomain(forName: suite) ?? [:]
        let secondRetained = fixtureValues.values.contains { ($0 as? Data) == second }

        let formatsKey = "appSettings.formats"
        defaults.set("synthetic non-Data object", forKey: formatsKey)
        let nonDataReported = store.unreadableDomains.contains(formatsKey)
        store.formats = .default
        let nonDataRetained = (defaults.persistentDomain(forName: suite) ?? [:]).values.contains {
            ($0 as? String) == "synthetic non-Data object"
        }

        let output: [String: Any] = [
            "firstFutureReported": firstReported,
            "loadPreservesPrimaryBytes": firstUnchangedAfterLoad,
            "ordinarySaveReplacesFuturePrimary": firstPrimaryReplaced,
            "firstFutureBackupRetained": firstBackupRetained,
            "secondFutureGenerationRetainedAfterSave": secondRetained,
            "nonDataObjectReportedAsUnreadable": nonDataReported,
            "nonDataObjectRetainedAfterSave": nonDataRetained,
            "scope": "synthetic isolated fixture; observations, not migration completion"
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
        defaults.removePersistentDomain(forName: suite)
        precondition(defaults.persistentDomain(forName: suite) == nil, "fixture cleanup failed")
    }
}
