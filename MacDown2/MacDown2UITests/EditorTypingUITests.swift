import XCTest

@MainActor
final class EditorTypingUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()

        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? "# Hello\n".write(to: fixturesDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", fixturesDir.appendingPathComponent("a.md").path,
        ]
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    func testTypingRoundTripsThroughDocument() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        // Focus the source text view and type some Markdown.
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let typedText = "## Subtitle\n"
        textView.typeText(typedText)

        // The typed content must round-trip into the source text view.
        XCTAssertTrue(textView.value as? String == "# Hello\n" + typedText)

        // The preview pane should eventually reflect the edited text.
        let preview = app.webViews.firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        // Dirty-close prompt on ⌘W confirms the document was mutated. Using the
        // keyboard shortcut avoids fragile localized menu-item title lookups.
        app.typeKey("w", modifierFlags: .command)

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.buttons["Discard Changes"].exists)
        sheet.buttons["Discard Changes"].click()
    }
}
