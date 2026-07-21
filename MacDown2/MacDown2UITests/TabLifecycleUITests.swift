import XCTest

final class TabLifecycleUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()

        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? "# File A".write(to: fixturesDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try? "# File B".write(to: fixturesDir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try? "# File C".write(to: fixturesDir.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fileAPath = fixturesDir.appendingPathComponent("a.md").path
        let fileBPath = fixturesDir.appendingPathComponent("b.md").path
        let fileCPath = fixturesDir.appendingPathComponent("c.md").path

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", "\(fileAPath),\(fileBPath),\(fileCPath)",
        ]
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    func testOpenFilesDirtyClosePromptAndRestore() {
        app.launch()
        app.activate()

        // Wait for the document window and native tab bar tabs.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let tabA = app.tabs.containing(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        let tabB = app.tabs.containing(NSPredicate(format: "title CONTAINS[c] %@", "b.md")).firstMatch
        let tabC = app.tabs.containing(NSPredicate(format: "title CONTAINS[c] %@", "c.md")).firstMatch
        XCTAssertTrue(tabA.waitForExistence(timeout: 5))
        XCTAssertTrue(tabB.exists)
        XCTAssertTrue(tabC.exists)

        // Activate b.md and dirty it using the debug menu.
        tabB.click()
        app.menuBars.menuBarItems["Debug"].click()
        app.menuBars.menuBarItems["Debug"].menuItems["Mark Active Tab Dirty"].click()

        // Close the active tab via the File menu.
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuBarItems["File"].menuItems["Close Tab"].click()

        // Verify the dirty-close alert appears.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.buttons["Discard Changes"].exists)

        // Cancel the close.
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(tabB.waitForExistence(timeout: 5))

        // Quit via the app menu so the delegate's applicationShouldTerminate
        // runs and saves the session before the app exits.
        app.menuBars.menuBarItems["MacDown 2"].click()
        app.menuBars.menuBarItems["MacDown 2"].menuItems["Quit MacDown 2"].click()

        // Wait for the session file to be written after termination.
        let sessionFile = sessionDir.appendingPathComponent("session.json")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: sessionFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path), "Session file was not written")

        // Relaunch with the same session directory but without -openFiles so
        // the app restores from the saved session.
        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
        ]
        app.launch()
        app.activate()

        // Verify all three tabs restored.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "a.md").waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "b.md").exists)
        XCTAssertTrue(tab(named: "c.md").exists)
    }

    private func tab(named name: String) -> XCUIElement {
        app.tabs.containing(NSPredicate(format: "title CONTAINS[c] %@", name)).firstMatch
    }
}
