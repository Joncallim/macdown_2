import Foundation
import XCTest

/// EPIC-11 §5 — app-level user workflows for the multi-format surface:
/// the JSON outline in the sidebar and preview pane, the HTML source ↔
/// rendered toggle, and the no-preview placeholder for source-only formats.
/// The package suites cover the underlying contracts; these assert the
/// accessibility-visible surface the user actually drives.
@MainActor
final class MultiFormatUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let sessionDir: URL
        let fixturesDir: URL
    }

    private func makeApp(contents: String, fileExtension: String) -> TestContext {
        let app = XCUIApplication()

        let fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fixture = fixturesDir.appendingPathComponent("fixture.\(fileExtension)")
        try? contents.write(to: fixture, atomically: true, encoding: .utf8)

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

    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Ensures the preview pane is visible. The layout preference lives in the
    /// shared UserDefaults suite, so a previous test run may have left the
    /// app in editor-only; drive the real ⌥⌘2 shortcut for determinism.
    private func ensureSplitLayout(_ app: XCUIApplication) {
        app.typeKey("2", modifierFlags: [.command, .option])
        let pane = element(app, id: "previewPane")
        XCTAssertTrue(pane.waitForExistence(timeout: 5), "preview pane did not appear after Split")
    }

    func testJSONOutlineShowsRowsAndPreviewPane() {
        let context = makeApp(contents: #"{"a":{"b":1},"c":[2,3]}"#, fileExtension: "json")
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        // The sidebar row for a member and the outline preview pane share the
        // format-neutral JSON channel.
        let row = element(context.app, id: "jsonOutlineRow-$.a")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar JSON outline row missing")
        ensureSplitLayout(context.app)
        let pane = element(context.app, id: "jsonOutlinePreviewPane")
        XCTAssertTrue(pane.waitForExistence(timeout: 5), "JSON outline preview pane missing")
    }

    func testInvalidJSONShowsDiagnosticInsteadOfStaleOutline() {
        let context = makeApp(contents: #"{"a":1,}"#, fileExtension: "json")
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        // The invalid document must surface the diagnostic state, never a
        // stale tree.
        ensureSplitLayout(context.app)
        let invalid = element(context.app, id: "jsonInvalidState")
        XCTAssertTrue(invalid.waitForExistence(timeout: 5), "invalid JSON diagnostic state missing")
    }

    func testHTMLPreviewTogglesSourceAndRendered() {
        let context = makeApp(contents: "<h1>Hello</h1>", fileExtension: "html")
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        ensureSplitLayout(context.app)
        let toggle = element(context.app, id: "htmlPreviewModeToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "HTML preview mode toggle missing")

        // The default is rendered (the web view host).
        let rendered = element(context.app, id: "htmlRenderedPane")
        XCTAssertTrue(rendered.waitForExistence(timeout: 5), "rendered pane missing")

        // Switch to source and the read-only source pane appears.
        context.app.segmentedControls.buttons["Source"].firstMatch.click()
        let source = element(context.app, id: "htmlSourcePane")
        XCTAssertTrue(source.waitForExistence(timeout: 5), "source pane did not appear after toggle")
    }

    func testPlainTextShowsNoPreviewPlaceholder() {
        let context = makeApp(contents: "just text", fileExtension: "txt")
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        ensureSplitLayout(context.app)
        let placeholder = element(context.app, id: "noPreviewPane")
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5), "no-preview placeholder missing")
    }
}
