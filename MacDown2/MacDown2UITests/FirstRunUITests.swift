import XCTest

/// Real UI-test execution for the E15 first-run welcome screen. `-UITesting`
/// alone always uses a fresh, isolated `UserDefaults` suite that never
/// reports first-run as complete, which would show this window in every one
/// of this target's other UI tests — `-ForceFirstRun` opts in explicitly so
/// only these tests exercise it (see `AppDelegate.init`'s doc comment).
@MainActor
final class FirstRunUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-ForceFirstRun",
        ]
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func testStartWritingDismissesWelcomeAndOpensAnEmptyDocument() {
        app.launch()
        app.activate()

        let welcome = app.otherElements["firstRunWelcomeView"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))

        app.buttons["firstRunStartWritingButton"].click()

        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(welcome.exists)
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "")
    }

    func testOpenSampleDocumentDismissesWelcomeAndOpensTheSampleText() {
        app.launch()
        app.activate()

        let welcome = app.otherElements["firstRunWelcomeView"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))

        app.buttons["firstRunOpenSampleButton"].click()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertFalse(welcome.exists)
        XCTAssertTrue((textView.value as? String)?.contains("Welcome to MacDown 2") == true)
    }
}
