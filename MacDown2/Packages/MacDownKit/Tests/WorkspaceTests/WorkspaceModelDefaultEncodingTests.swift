@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// `newManagedDocument(encoding:)`'s one job: seed a brand-new, never-saved
/// document's `FileEncodingMetadata` from the caller (the App target's
/// Formats-pane preference), without disturbing the UTF-8 default every
/// other caller still gets (epic-13-implementation.md §17 Slice 4). Kept in
/// its own file rather than growing `WorkspaceModelTests`/
/// `WorkspaceLifetimeTests`, both already close to the type-body-length
/// budget.
@MainActor
@Suite("WorkspaceModel default encoding")
struct WorkspaceModelDefaultEncodingTests {
    @Test func newManagedDocumentUsesTheProvidedEncoding() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let utf16 = FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)

        _ = await model.newManagedDocument(encoding: utf16)

        #expect(model.activeDocument?.encoding == utf16)
    }

    @Test func newManagedDocumentDefaultsToUTF8WhenNoEncodingIsProvided() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        _ = await model.newManagedDocument()

        #expect(model.activeDocument?.encoding == .utf8Default)
    }
}
