@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Round-4 review (b17bcf15) P2: `renewRecoveryLifetime` checked the document was current BEFORE awaiting the
/// persist and then published the older renewed copy unconditionally, reverting keystrokes typed during the await
/// (54 of 60 yield offsets); an edit during the epoch mint left the window on the retired lifetime (5 of 60).
@MainActor
struct WorkspaceRenewRecoveryLifetimeTests {
    @Test func anEditAtAnyPointDuringTheRenewIsKeptAndTheLifetimeIsRenewed() async throws {
        var reverted: [Int] = []
        var notRenewed: [Int] = []
        for yields in 0 ..< 60 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let store = TabStore(
                sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
                recoveryBuffer: buffer
            )
            let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft2")
            store.newTab(document: document)
            let model = WorkspaceModel(tabStore: store)
            let renew = Task { @MainActor in await model.renewRecoveryLifetime(retiredFrom: document) }
            for _ in 0 ..< yields {
                await Task.yield()
            }
            model.tabStore.updateActiveDocument { $0.updatingText("typed \(yields)") }
            await renew.value

            let active = try #require(model.tabStore.activeDocument)
            if active.text != "typed \(yields)" {
                reverted.append(yields)
            }
            if active.recoveryEpoch == document.recoveryEpoch {
                notRenewed.append(yields)
            }
        }
        #expect(reverted.isEmpty, "the edit was reverted at yield offsets \(reverted)")
        #expect(notRenewed.isEmpty, "the window stayed on the retired lifetime at yield offsets \(notRenewed)")
    }
}
