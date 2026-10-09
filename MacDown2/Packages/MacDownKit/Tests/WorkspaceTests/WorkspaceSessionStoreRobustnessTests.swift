import Foundation
import Testing
@testable import Workspace

/// `loadSession` returned nil when ANY field of ANY tab failed to decode (for example an unknown enum value
/// after an app downgrade): no restore, and the next autosave overwrote `session.json`, orphaning the dirty
/// recovery of every tab.
@MainActor
struct WorkspaceSessionStoreRobustnessTests {
    private struct Fixture {
        let store: WorkspaceSessionStore
        let url: URL
        let directory: URL
    }

    private func makeStore() -> Fixture {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("session.json")
        return Fixture(store: WorkspaceSessionStore(fileURL: url), url: url, directory: directory)
    }

    @Test func oneUndecodableTabCostsThatTabNotTheSession() throws {
        let fixture = makeStore()
        let (store, url, directory) = (fixture.store, fixture.url, fixture.directory)
        defer { cleanup(directory) }
        let good = UUID()
        let bad = UUID()
        let json = """
        {"version":1,"activeTabID":"\(good.uuidString)","tabs":[
          {"id":"\(bad.uuidString)","isPinned":false,"previewLayout":"holographic-from-the-future"},
          {"id":"\(good.uuidString)","isPinned":true,"untitledDocumentID":"abc"}
        ]}
        """
        try Data(json.utf8).write(to: url)

        let session = try #require(store.loadSession())

        #expect(session.tabs.map(\.id) == [good])
        #expect(session.activeTabID == good)
    }

    /// The lenient decode drops the bad tab silently; the next autosave then removed it (and its recovery pointer)
    /// from `session.json` with no copy anywhere.
    @Test func aSessionThatLostATabWhileDecodingIsPreservedBeforeTheAutosave() throws {
        let fixture = makeStore()
        defer { cleanup(fixture.directory) }
        let json = """
        {"version":1,"tabs":[
          {"id":"\(UUID().uuidString)","isPinned":"someFutureEnum","untitledDocumentID":"u1"},
          {"id":"\(UUID().uuidString)","isPinned":false}
        ]}
        """
        try Data(json.utf8).write(to: fixture.url)

        #expect(fixture.store.loadSession()?.tabs.count == 1)
        fixture.store.saveSession(WorkspaceSession.empty)

        #expect(try Data(contentsOf: fixture.url.appendingPathExtension("unreadable")) == Data(json.utf8))
    }

    @Test func aFullyDecodedSessionLeavesNoBackup() {
        let fixture = makeStore()
        defer { cleanup(fixture.directory) }
        fixture.store.saveSession(WorkspaceSession(tabs: [TabRecord(id: UUID())], activeTabID: nil))

        #expect(fixture.store.loadSession()?.tabs.count == 1)

        #expect(!FileManager.default.fileExists(atPath: fixture.url.appendingPathExtension("unreadable").path))
    }

    @Test func anUnreadableSessionFileIsPreservedBeforeAnAutosaveCanReplaceIt() throws {
        let fixture = makeStore()
        let (store, url, directory) = (fixture.store, fixture.url, fixture.directory)
        defer { cleanup(directory) }
        let garbage = Data("{ this is not a session".utf8)
        try garbage.write(to: url)

        #expect(store.loadSession() == nil)
        store.saveSession(WorkspaceSession.empty)

        let backup = url.appendingPathExtension("unreadable")
        #expect(try Data(contentsOf: backup) == garbage)
    }

    @Test func aNewerVersionIsPreservedToo() throws {
        let fixture = makeStore()
        let (store, url, directory) = (fixture.store, fixture.url, fixture.directory)
        defer { cleanup(directory) }
        let newer = Data(#"{"version":99,"tabs":[]}"#.utf8)
        try newer.write(to: url)

        #expect(store.loadSession() == nil)

        #expect(try Data(contentsOf: url.appendingPathExtension("unreadable")) == newer)
    }

    @Test func aNormalSessionStillRoundTrips() {
        let fixture = makeStore()
        let (store, directory) = (fixture.store, fixture.directory)
        defer { cleanup(directory) }
        let session = WorkspaceSession(tabs: [TabRecord(id: UUID(), isPinned: true)], activeTabID: nil)

        store.saveSession(session)

        #expect(store.loadSession() == session)
    }
}
