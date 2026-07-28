import Foundation
import XCTest

@MainActor
final class PreviewLayoutUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let sessionDir: URL
        let fixturesDir: URL
    }

    private func makeApp() -> TestContext {
        let app = XCUIApplication()

        let fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fixture = fixturesDir.appendingPathComponent("a.md")
        try? "# Hello\n".write(to: fixture, atomically: true, encoding: .utf8)

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

    func testLayoutKeyboardShortcutsTogglePanes() {
        let context = makeApp()
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let textView = context.app.textViews.firstMatch
        let previewPane = context.app.descendants(matching: .any)
            .matching(identifier: "previewPane")
            .firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertTrue(previewPane.waitForExistence(timeout: 5))

        // Preview Only hides the editor.
        choosePreviewOnly(context.app)
        XCTAssertFalse(textView.exists)
        XCTAssertTrue(previewPane.waitForExistence(timeout: 5))

        // Editor Only hides the preview.
        chooseEditorOnly(context.app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertFalse(previewPane.exists)

        // Split restores both panes.
        chooseSplit(context.app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertTrue(previewPane.waitForExistence(timeout: 5))
    }

    func testLayoutPersistsAcrossSessionRestore() {
        let context = makeApp()
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        choosePreviewOnly(context.app)

        // Allow the debounced session save to complete before terminating.
        Thread.sleep(forTimeInterval: 1.0)

        context.app.terminate()
        XCTAssertTrue(context.app.wait(for: .notRunning, timeout: 5))

        // Wait for the session file to be written after termination and log its
        // contents so session-restore failures can be distinguished from save
        // failures.
        let sessionFile = context.sessionDir.appendingPathComponent("session.json")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: sessionFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let contents = (try? Data(contentsOf: sessionFile))
            .flatMap { String(data: $0, encoding: .utf8) }
        if let contents {
            XCTContext.runActivity(named: "Session file contents") { _ in
                print("Session file: \(contents)")
            }
        } else {
            XCTContext.runActivity(named: "Session file missing") { _ in
                print("Session file missing at \(sessionFile.path)")
            }
        }

        // Relaunch with the same session directory but without -openFiles so
        // the app restores from the saved session.
        context.app.launchArguments = [
            "-UITesting",
            "-sessionDir", context.sessionDir.path,
        ]
        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let textView = context.app.textViews.firstMatch
        let previewPane = context.app.descendants(matching: .any)
            .matching(identifier: "previewPane")
            .firstMatch
        XCTAssertFalse(textView.exists)
        XCTAssertTrue(previewPane.waitForExistence(timeout: 5))
    }

    private func chooseEditorOnly(_ app: XCUIApplication) {
        app.typeKey("1", modifierFlags: [.command, .option])
    }

    private func chooseSplit(_ app: XCUIApplication) {
        app.typeKey("2", modifierFlags: [.command, .option])
    }

    private func choosePreviewOnly(_ app: XCUIApplication) {
        app.typeKey("3", modifierFlags: [.command, .option])
    }
}
