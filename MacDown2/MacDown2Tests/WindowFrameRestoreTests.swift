import AppKit
import AppSettings
import Foundation
@testable import MacDown2
import Testing

/// `setFrameAutosaveName` restored the saved frame and the unconditional `setContentSize(1200x800)` right after it
/// shrank the window and re-saved that, so a window's size was never remembered. Also: the editor's Size setting
/// did nothing for a family the system lacks (the default "SF Mono" is not an installed family), because the
/// fallback ignored the descriptor's size.
@MainActor
struct WindowFrameRestoreTests {
    @Test func aSavedFrameIsDetectedByItsAutosaveName() throws {
        let defaults = try #require(UserDefaults(suiteName: "frame-restore-\(UUID().uuidString)"))
        #expect(!WindowController.hasSavedFrame(named: "Probe", defaults: defaults))

        defaults.set("10 10 1500 900 0 0 1920 1080 ", forKey: "NSWindow Frame Probe")

        #expect(WindowController.hasSavedFrame(named: "Probe", defaults: defaults))
    }

    @Test func theEditorFontSizeAppliesEvenWhenTheFamilyIsNotInstalled() {
        let font = DocumentEditorSplitView.resolvedFont(
            from: FontDescriptor(familyName: "No Such Family \(UUID().uuidString)", size: 21)
        )

        #expect(font.pointSize == 21)
        #expect(font.isFixedPitch)
    }
}
