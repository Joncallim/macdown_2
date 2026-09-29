import FileCore
import Foundation
import Testing
@testable import Workspace

/// EPIC-22 Slice 9d — the per-tab Syntax Mode override.
@MainActor
@Suite("SyntaxModeOverride")
struct SyntaxModeOverrideTests {
    private let registry = FileFormatRegistry()

    private func format(_ id: String) throws -> FileFormat {
        try #require(registry.formats.first { $0.id == id })
    }

    private struct OpenedStore {
        let store: TabStore
        let tabID: UUID
        let directory: URL
    }

    private func openedStore(_ name: String, contents: String = "x") async throws -> OpenedStore {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent(name)
        _ = try FileStore().write(contents, to: fileURL)
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        )
        _ = await store.openFileInTab(fileURL)
        return try OpenedStore(store: store, tabID: #require(store.activeTabID), directory: directory)
    }

    // MARK: - Resolution

    @Test func noOverrideFollowsTheDocumentFormat() throws {
        let markdown = try format("markdown")
        #expect(registry.syntaxFormat(for: markdown, override: nil).id == "markdown")
    }

    @Test func overrideSubstitutesTheModeFormat() throws {
        let plain = try format("plaintext")
        let override = SyntaxModeOverride(modeFormatID: "swift", baseFormatID: "plaintext")
        let effective = registry.syntaxFormat(for: plain, override: override)
        #expect(effective.id == "swift")
        #expect(effective.highlightLanguageID == "swift")
        #expect(registry.isActive(override, for: plain))
    }

    @Test func overrideMadeAgainstAnotherBaseFormatIsIgnored() throws {
        let markdown = try format("markdown")
        let stale = SyntaxModeOverride(modeFormatID: "swift", baseFormatID: "plaintext")
        #expect(registry.syntaxFormat(for: markdown, override: stale).id == "markdown")
        #expect(!registry.isActive(stale, for: markdown))
    }

    @Test func overrideNamingAnUnregisteredModeIsIgnored() throws {
        let plain = try format("plaintext")
        let unknown = SyntaxModeOverride(modeFormatID: "cobol", baseFormatID: "plaintext")
        #expect(registry.syntaxFormat(for: plain, override: unknown).id == "plaintext")
    }

    // MARK: - Tab state

    @Test func setSyntaxModeStoresOverrideAgainstTheCurrentFormat() async throws {
        let opened = try await openedStore("notes.txt")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }

        store.setSyntaxMode("python", for: tabID)
        let tab = try #require(store.tabs.first { $0.id == tabID })
        #expect(tab.syntaxOverride == SyntaxModeOverride(modeFormatID: "python", baseFormatID: "plaintext"))
        #expect(tab.syntaxFormat.id == "python")
        #expect(tab.document.format.id == "plaintext")
    }

    @Test func choosingAutomaticOrTheOwnFormatClearsTheOverride() async throws {
        let opened = try await openedStore("notes.txt")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }

        store.setSyntaxMode("python", for: tabID)
        store.setSyntaxMode(nil, for: tabID)
        #expect(store.tabs.first { $0.id == tabID }?.syntaxOverride == nil)

        store.setSyntaxMode("python", for: tabID)
        store.setSyntaxMode("plaintext", for: tabID)
        #expect(store.tabs.first { $0.id == tabID }?.syntaxOverride == nil)
    }

    @Test func unregisteredModeIsRejected() async throws {
        let opened = try await openedStore("notes.txt")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }

        store.setSyntaxMode("cobol", for: tabID)
        #expect(store.tabs.first { $0.id == tabID }?.syntaxOverride == nil)
    }

    @Test func overrideDoesNotMakeTheDocumentDirtyOrChangeItsPreviewRouting() async throws {
        let opened = try await openedStore("notes.md", contents: "# Hi\n")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }

        store.setSyntaxMode("plaintext", for: tabID)
        let tab = try #require(store.tabs.first { $0.id == tabID })
        #expect(tab.document.state == .clean)
        #expect(tab.document.format.id == "markdown")
        #expect(tab.document.format.previewCapability == .markdown)
        #expect(tab.syntaxFormat.previewCapability == PreviewCapability.none)
        #expect(tab.syntaxFormat.highlightLanguageID == nil)
    }

    @Test func overrideFollowsThePinToggleAndSurvivesSessionRestore() async throws {
        let opened = try await openedStore("notes.txt")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }
        store.setSyntaxMode("sql", for: tabID)
        store.togglePin(tabID)
        #expect(store.tabs.first { $0.id == tabID }?.syntaxOverride?.modeFormatID == "sql")
        await store.saveSession()

        let restored = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        )
        await restored.restoreSessionIfNeeded()
        #expect(restored.tabs.first?.syntaxOverride == SyntaxModeOverride(
            modeFormatID: "sql",
            baseFormatID: "plaintext"
        ))
    }

    @Test func overrideRetiresWhenSaveAsChangesTheFormat() async throws {
        let opened = try await openedStore("notes.txt")
        let (store, tabID, directory) = (opened.store, opened.tabID, opened.directory)
        defer { cleanup(directory) }
        store.setSyntaxMode("python", for: tabID)

        let index = try #require(store.tabs.firstIndex { $0.id == tabID })
        store.tabs[index].document = try store.tabs[index].document
            .saveAs(directory.appendingPathComponent("notes.md"))

        let tab = store.tabs[index]
        #expect(tab.document.format.id == "markdown")
        #expect(tab.syntaxFormat.id == "markdown")
        #expect(tab.syntaxOverride == nil)

        // Returning to the original format must not revive the old override.
        store.tabs[index].document = try store.tabs[index].document
            .saveAs(directory.appendingPathComponent("notes.txt"))
        #expect(store.tabs[index].syntaxFormat.id == "plaintext")
    }

    // MARK: - Session encoding

    @Test func tabRecordRoundTripsTheOverrideAndLegacyRecordsDecodeWithout() throws {
        let record = TabRecord(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
            syntaxOverride: SyntaxModeOverride(modeFormatID: "ruby", baseFormatID: "plaintext")
        )
        let decoded = try JSONDecoder().decode(TabRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)

        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"isPinned\":false}".utf8)
        #expect(try JSONDecoder().decode(TabRecord.self, from: legacy).syntaxOverride == nil)
    }
}
