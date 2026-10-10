@testable import AppSettings
import Foundation
import Testing

/// #53 SETTINGS-COMPAT: the pre-E22 editor blob (no `showsStatusBar`) must keep every valid user value, and anything
/// this build cannot read must be retained verbatim and reported, never replaced by defaults.
@MainActor
struct SettingsCompatibilityTests {
    private static let editorKey = "appSettings.editor"

    private func isolated(_ body: (UserDefaults, UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let suite = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("no suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suite) }
        try body(defaults, UserDefaultsAppSettingsStore(defaults: defaults))
    }

    private func editorJSON(statusBar: String? = nil, width: String = "2", extra: String = "",
                            omit: String? = nil) -> Data {
        var fields = [
            "\"font\":{\"familyName\":\"Menlo\",\"size\":15}",
            "\"wrapsLines\":false",
            "\"showsInvisibles\":true",
            "\"indentationWidth\":\(width)",
            "\"assistsEnabled\":false",
            "\"continuesMarkdownPrefixes\":false",
            "\"completesMatchingCharacters\":false",
            "\"convertsTabsToSpaces\":false",
            "\"smartHome\":false",
            "\"autoIncrementOrderedLists\":false",
        ]
        if let statusBar {
            fields.append("\"showsStatusBar\":\(statusBar)")
        }
        if !extra.isEmpty {
            fields.append(extra)
        }
        if let omit {
            fields.removeAll { $0.hasPrefix("\"\(omit)\"") }
        }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    @Test func aPreE22BlobKeepsEveryUserValueAndDefaultsOnlyTheMissingField() {
        isolated { defaults, store in
            defaults.set(editorJSON(), forKey: Self.editorKey)

            let editor = store.editor

            #expect(editor.font == FontDescriptor(familyName: "Menlo", size: 15))
            #expect(editor.indentationWidth == 2)
            #expect(!editor.assistsEnabled && !editor.wrapsLines && !editor.smartHome)
            #expect(editor.showsInvisibles)
            #expect(editor.showsStatusBar, "the one missing additive field takes its documented default")
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    @Test func aPresentFalseStatusBarStaysFalse() {
        isolated { defaults, store in
            defaults.set(editorJSON(statusBar: "false"), forKey: Self.editorKey)
            #expect(!store.editor.showsStatusBar)
        }
    }

    @Test func aMissingOldMandatoryFieldIsUnreadableAndTheRawBytesSurviveASave() {
        isolated { defaults, store in
            var store = store
            let original = editorJSON(omit: "font")
            defaults.set(original, forKey: Self.editorKey)

            #expect(store.editor == .default, "session fallback only")
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == original, "loading never rewrites the blob")

            store.editor = EditorSettings(indentationWidth: 3)

            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == original)
            #expect(store.editor.indentationWidth == 3)
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    @Test(arguments: ["0", "9", "-1", "\"wide\"", "2.5"])
    func anInvalidOrOutOfRangeIndentationIsUnreadableNotSilentlyClamped(width: String) {
        isolated { defaults, store in
            defaults.set(editorJSON(width: width), forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
        }
    }

    @Test func aNewerSchemaVersionIsKeptAndNotRewrittenByAnOlderBuild() {
        isolated { defaults, store in
            var store = store
            let future = editorJSON(extra: "\"schemaVersion\":2,\"futureOnlyField\":\"keep me\"")
            defaults.set(future, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = EditorSettings(indentationWidth: 5)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == future)
        }
    }

    @Test func aCurrentOrAbsentSchemaVersionIsReadable() {
        isolated { defaults, store in
            defaults.set(editorJSON(extra: "\"schemaVersion\":1"), forKey: Self.editorKey)
            #expect(store.editor.indentationWidth == 2)
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    @Test func corruptBytesAreRetainedAndReported() {
        isolated { defaults, store in
            var store = store
            let corrupt = Data([0x7B, 0xFF, 0x00, 0x22])
            defaults.set(corrupt, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = .default
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == corrupt)
        }
    }

    @Test func thePreservedCopyIsTheFirstUnreadableBlobAndRepeatedLaunchesAreIdempotent() {
        isolated { defaults, store in
            var store = store
            let first = Data("not json".utf8)
            defaults.set(first, forKey: Self.editorKey)
            store.editor = EditorSettings(indentationWidth: 2) // preserves `first`, writes valid data
            defaults.set(Data("also not json".utf8), forKey: Self.editorKey) // a second unreadable generation
            store.editor = EditorSettings(indentationWidth: 3)

            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == first, "never overwritten once kept")

            // Repeated reads are stable and never write.
            let written = defaults.data(forKey: Self.editorKey)
            _ = store.editor
            _ = store.editor
            #expect(defaults.data(forKey: Self.editorKey) == written)
        }
    }

    @Test func validCurrentDataRoundTripsWithoutPreservingAnything() {
        isolated { defaults, store in
            var store = store
            store.editor = EditorSettings(showsStatusBar: false, indentationWidth: 6)
            store.editor = EditorSettings(showsStatusBar: false, indentationWidth: 7)

            #expect(store.editor.indentationWidth == 7 && !store.editor.showsStatusBar)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == nil)
            #expect(defaults.data(forKey: Self.editorKey + ".preservedUnreadable") == nil)
        }
    }
}
