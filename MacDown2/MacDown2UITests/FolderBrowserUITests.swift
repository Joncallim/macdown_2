import XCTest

@MainActor
final class FolderBrowserUITests: XCTestCase {
    func testNoRootOffersOpenFolderAndShortcutHint() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["Open Folder…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["⌘⇧O opens a folder"].exists)
    }

    func testFolderSectionHasStableAccessibilityIdentity() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "folderSection").firstMatch
            .waitForExistence(timeout: 5))
    }
}
