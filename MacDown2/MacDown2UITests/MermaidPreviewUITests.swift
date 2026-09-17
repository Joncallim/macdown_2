import Foundation
import XCTest

/// Real XCUITest evidence for E20's Preview wiring (epic-20-implementation.md
/// §14, §17 Slice 6) — genuine end-to-end proof that a ```mermaid``` fence
/// renders in the live, running app, via accessibility-tree queries rather
/// than screen capture (this session's screen/display-capture access was
/// unavailable for a manual visual dogfood pass; this is real, independent,
/// automated evidence in its place, not a substitute for a human still
/// looking at it eventually).
@MainActor
final class MermaidPreviewUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let sessionDir: URL
        let fixturesDir: URL
    }

    private func makeApp(fixtureContents: String) -> TestContext {
        let app = XCUIApplication()

        let fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fixture = fixturesDir.appendingPathComponent("a.md")
        try? fixtureContents.write(to: fixture, atomically: true, encoding: .utf8)

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

    func testAMermaidFenceRendersAsADiagramImageInTheLivePreview() {
        let text = "# Title\n\n```mermaid\ngraph TD; A-->B;\n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        // The real render pipeline (offscreen WKWebView pool warm-up +
        // Mermaid execution + rasterization) is slower than ordinary
        // Markdown text layout, hence the longer timeout than other
        // Preview UI tests use.
        let diagramImage = context.app.descendants(matching: .any)
            .matching(identifier: "mermaidDiagramImage")
            .firstMatch
        XCTAssertTrue(diagramImage.waitForExistence(timeout: 20))

        // The loading placeholder and error banner must not also be present
        // once the real diagram has rendered.
        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "mermaidDiagramLoading").firstMatch
            .exists)
        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "mermaidDiagramError").firstMatch
            .exists)
    }

    func testAMalformedMermaidFenceShowsAnInlineErrorInTheLivePreview() {
        let text = "```mermaid\ngraph TD; A-->\n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let errorBanner = context.app.descendants(matching: .any)
            .matching(identifier: "mermaidDiagramError")
            .firstMatch
        XCTAssertTrue(errorBanner.waitForExistence(timeout: 20))
    }
}
