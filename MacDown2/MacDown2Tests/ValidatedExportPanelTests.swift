import AppKit
@testable import MacDown2
import Testing

@MainActor
@Suite("Disabled validated export sheet cancellation")
struct ValidatedExportPanelTests {
    @Test func taskCancellationDismissesTheRealSheet() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        var presented = false
        let task = Task { @MainActor in
            await ValidatedExportPanel.chooseTarget(
                in: window, defaultName: "cancelled", directory: nil
            ) { panel in
                presented = panel.sheetParent === window
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !presented, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(presented)
        task.cancel()
        let result = await task.value
        #expect(result == nil)
    }
}
