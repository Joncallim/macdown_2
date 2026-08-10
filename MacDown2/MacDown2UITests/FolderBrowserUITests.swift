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
        XCTAssertTrue(app.buttons["openFolderButton"].waitForExistence(timeout: 5))
    }

    func testCreateFileAddsARowAndOffersRename() throws {
        let folder = try temporaryDirectory()
        let seed = try temporaryFile(named: "seed.md")
        let app = launch(folder: folder, opening: seed)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: seed.deletingLastPathComponent())
        }

        let newFile = app.buttons["newFileButton"]
        XCTAssertTrue(newFile.waitForExistence(timeout: 8))
        newFile.click()

        let createdRow = app.descendants(matching: .any)
            .matching(identifier: "fileRow-untitled.md")
            .firstMatch
        XCTAssertTrue(createdRow.waitForExistence(timeout: 8))

        createdRow.rightClick()
        let rename = app.menuItems["fileTreeRenameAction"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("untitled.md").path))
    }

    func testMoveToTrashOffersDestructiveConfirmationAction() throws {
        let folder = try temporaryDirectory()
        let seed = try temporaryFile(named: "seed.md")
        let file = folder.appendingPathComponent("delete-me.md")
        try Data("delete me".utf8).write(to: file)
        let app = launch(folder: folder, opening: seed)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: seed.deletingLastPathComponent())
        }

        let row = app.descendants(matching: .any).matching(identifier: "fileRow-delete-me.md").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.rightClick()
        let trash = app.menuItems["fileTreeTrashAction"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    private func launch(folder: URL, opening file: URL) -> XCUIApplication {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-sessionDir", session.path,
            "-openFiles", file.path,
            "-openFolder", folder.path,
        ]
        app.launch()
        return app
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryFile(named name: String) throws -> URL {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent(name)
        try Data("seed".utf8).write(to: file)
        return file
    }
}
