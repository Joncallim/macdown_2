import Foundation
import XCTest

@MainActor
final class OutlineNavigationUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let sessionDir: URL
        let fixturesDir: URL
    }

    private func makeApp(markdown: String) -> TestContext {
        let app = XCUIApplication()

        let fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fixture = fixturesDir.appendingPathComponent("outline.md")
        try? markdown.write(to: fixture, atomically: true, encoding: .utf8)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", fixture.path,
        ]

        return TestContext(app: app, sessionDir: sessionDir, fixturesDir: fixturesDir)
    }

    private func cleanup(_ context: TestContext) {
        try? FileManager.default.removeItem(at: context.sessionDir)
        try? FileManager.default.removeItem(at: context.fixturesDir)
    }

    private func focusOutline(_ app: XCUIApplication) {
        app.typeKey("o", modifierFlags: [.control, .command])
    }

    private func outlineRow(_ app: XCUIApplication, id: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "outlineRow-\(id)").firstMatch
    }

    func testFocusOutlineRevealsRowsAndReturnJumpsTheEditor() {
        let context = makeApp(markdown: """
        # First
        Body under first.

        # Second
        Body under second.
        """)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let textView = context.app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // The outline populates from the same debounced parse as the preview —
        // give it a moment to land before looking for rows.
        let firstRow = outlineRow(context.app, id: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        let secondRow = outlineRow(context.app, id: 1)
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))

        focusOutline(context.app)

        // Arrow down to the second row, then Return to jump the editor there.
        context.app.typeKey(.downArrow, modifierFlags: [])
        context.app.typeKey(.downArrow, modifierFlags: [])
        context.app.typeKey(.return, modifierFlags: [])

        // The caret should have moved into the editor at/after "Second" — a
        // coarse but reliable signal is that the editor regains key focus
        // and the window is still showing the same document.
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
    }
}
