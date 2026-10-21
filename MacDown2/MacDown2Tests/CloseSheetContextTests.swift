@testable import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// PR #468 review P2: replacing the `mutationGeneration` comparison in the close sheet's context check dropped the
/// only thing that noticed the backing file vanishing while the "Save changes?" sheet was up (it changes only the
/// backing state and the generation). "Discard" would then discard the last copy without the Save-a-Copy offer.
@MainActor
struct CloseSheetContextTests {
    @Test func aVanishedBackingFileIsNoLongerTheDocumentTheSheetAskedAbout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try "disk".write(to: file, atomically: true, encoding: .utf8)
        let presented = try FileDocument(fileURL: file).load().updatingText("local edits")
        let context = CloseSheetContext(presented)

        #expect(WindowController.presentedContextMatches(presented, context), "control: the same document matches")
        let vanished = presented.markingBackingUnavailable(.missingOrMoved)
        #expect(vanished.text == presented.text && vanished.state == presented.state)
        #expect(
            !WindowController.presentedContextMatches(vanished, context),
            "the file vanished while the sheet was up: the close flow must run again"
        )
    }

    @Test func aBareGenerationBumpStillMatches() {
        let presented = FileDocument(text: "x").updatingText("y")
        let context = CloseSheetContext(presented)

        #expect(WindowController.presentedContextMatches(presented.withFreshRecoveryLifetime(), context))
    }

    @Test func closePromptRemainsTruthfulIfBackingDisappearsWhileSheetIsOpen() {
        let alert = WindowController.makeDirtyCloseAlert(fileName: "draft.md")

        #expect(alert.buttons[0].title == "Save Changes")
        #expect(alert.informativeText.contains("location"))
        #expect(alert.informativeText.contains("draft.md"))
    }

    @Test func aDisposedExplicitPanelOriginCancelsInsteadOfGoingModal() {
        let missingOrigin = NSFilePanelProvider(window: nil)
        guard case .cancelled = missingOrigin.presentation(keyWindow: nil) else {
            Issue.record("A disposed explicit origin must cancel its panel request")
            return
        }

        let applicationOrigin = NSFilePanelProvider()
        guard case .modal = applicationOrigin.presentation(keyWindow: nil) else {
            Issue.record("An application command without a key window may use a modal panel")
            return
        }
    }
}
