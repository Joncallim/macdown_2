import Foundation
import XCTest

@MainActor
final class PreviewKeyboardUITests: XCTestCase {
    func testHTMLPreviewCommandsAndFolderChooser() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let fixture = fixtureDirectory.appendingPathComponent("preview.html")
        try "<h1>Keyboard fixture</h1>".write(to: fixture, atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-sessionDir", sessionDirectory.path, "-openFiles", fixture.path]
        defer { app.terminate() }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let rendered = app.descendants(matching: .any).matching(identifier: "htmlRenderedPane").firstMatch
        let source = app.descendants(matching: .any).matching(identifier: "htmlSourcePane").firstMatch
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        app.typeKey("p", modifierFlags: [.command, .shift])
        let palette = app.textFields["commandPaletteSearchField"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        let viewMenu = app.menuBars.menuBarItems["View"]
        let commandNames = ["Choose Preview Resources Folder…", "Show HTML Source", "Show Rendered HTML"]
        viewMenu.click()
        for name in commandNames {
            let item = viewMenu.menuItems[name].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing menu item: \(name)")
            assertEventually(item, property: "enabled", is: false)
        }
        app.typeKey(.escape, modifierFlags: []) // Close the menu.
        app.typeKey(.escape, modifierFlags: []) // Dismiss the palette.
        assertEventually(palette, property: "exists", is: false)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        viewMenu.click()
        for name in commandNames {
            let item = viewMenu.menuItems[name].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing menu item: \(name)")
            assertEventually(item, property: "enabled", is: true)
        }
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("4", modifierFlags: [.command, .option])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertFalse(rendered.exists)
        app.typeKey("5", modifierFlags: [.command, .option])
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        app.typeKey("r", modifierFlags: [.command, .option])
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["allowPreviewResources"].waitForExistence(timeout: 5))
    }

    private func assertEventually(
        _ element: XCUIElement, property: String, is expected: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "%K == %@", property, NSNumber(value: expected))
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 5), .completed, file: file, line: line)
    }
}
