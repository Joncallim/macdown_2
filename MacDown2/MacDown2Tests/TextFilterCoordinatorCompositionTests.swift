import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextFilters
import Themes
import Workspace

/// Composition (IME) fail-open coverage for `TextFilterCoordinator`, split from `TextFilterCoordinatorTests` for size.
@MainActor
extension TextFilterCoordinatorTests {
    /// Cross-feature review (2026-10-11), F1: a composition started while the filter ran is invisible to the
    /// content-revision baseline (marked text posts no `didChange`), so the result was applied at stale offsets.
    @Test func aCompositionStartedWhileTheFilterRunsDiscardsTheResultAndKeepsTheComposition() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "two"
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let runTask = Task {
            await fixture.coordinator.textFilterCoordinator.run(command, against: target)
        }
        try await Task.sleep(for: .milliseconds(100))

        textSystem.textView.setMarkedText(
            "\u{306B}\u{307B}\u{3093}",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        #expect(textSystem.textView.hasMarkedText())
        let textDuringComposition = textSystem.text

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await runTask.value

        #expect(!textSystem.textView.string.contains("TWO"), "the uppercased filter output must not have been applied")
        #expect(textSystem.text == textDuringComposition, "the filter result must not splice into the composition")
        #expect(textSystem.textView.hasMarkedText(), "the composition must still be active")
    }
}
