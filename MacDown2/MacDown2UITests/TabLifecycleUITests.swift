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
        let tabA = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        let tabB = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "b.md")).firstMatch
        let tabC = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "c.md")).firstMatch
        XCTAssertTrue(tabA.waitForExistence(timeout: 5))
        XCTAssertTrue(tabB.exists)
        XCTAssertTrue(tabC.exists)

        // Activate b.md and dirty it using the debug menu. Use the app's own
        // "Select Tab 2" command so the native tab switch also makes b.md's
        // window key; a raw accessibility click on the tab bar does not reliably
        // update the key window under UI automation.
        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuBarItems["Window"].menuItems["Select Tab 2"].firstMatch.click()

        // Wait for the tab switch to complete so the next command targets the
        // correct window. The native tab bar exposes selection as `value == 1`
        // on macOS 26; if this assertion flakes on a future macOS version,
        // switch to an `isSelected == YES` predicate if AppKit exposes it.
        let selectedB = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "b.md"
        )).firstMatch
        XCTAssertTrue(selectedB.waitForExistence(timeout: 5))

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

        // Terminate the app. NSRunningApplication.terminate() delivers a 'quit'
        // Apple event that routes through applicationShouldTerminate, which saves
        // the session before exiting. Using terminate() avoids a menu-dismissal
        // focus switch that can reorder native tabs under UI automation.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

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

        // Verify all three tabs restored and b.md is selected again.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "a.md").waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "b.md").exists)
        XCTAssertTrue(tab(named: "c.md").exists)

        let selectedTab = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "b.md"
        )).firstMatch
        XCTAssertTrue(
            selectedTab.waitForExistence(timeout: 5),
            "Expected b.md to be the restored active tab"
        )
    }

    private func tab(named name: String) -> XCUIElement {
        app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", name)).firstMatch
    }
}
