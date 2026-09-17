import Foundation
import XCTest

/// Real XCUITest evidence for E21's Preview wiring (epic-21-implementation.md
/// Slice 6), mirroring `MermaidPreviewUITests`' exact shape — genuine
/// end-to-end proof that ```d2``` and ```dot```/```graphviz``` fences
/// render in the live, running app, via accessibility-tree queries.
@MainActor
final class D2GraphvizPreviewUITests: XCTestCase {
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

    func testAD2FenceRendersAsADiagramImageInTheLivePreview() {
        let text = "# Title\n\n```d2\na -> b\n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        // The real render pipeline (offscreen WKWebView pool warm-up + D2
        // WASM execution) is slower than ordinary Markdown text layout,
        // hence the longer timeout than other Preview UI tests use.
        let diagramImage = context.app.descendants(matching: .any)
            .matching(identifier: "d2DiagramImage")
            .firstMatch
        XCTAssertTrue(diagramImage.waitForExistence(timeout: 20))

        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "d2DiagramLoading").firstMatch
            .exists)
        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "d2DiagramError").firstMatch
            .exists)
    }

    func testAMalformedD2FenceShowsAnInlineErrorInTheLivePreview() {
        let text = "```d2\n{{{ not valid d2 ][\n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let errorBanner = context.app.descendants(matching: .any)
            .matching(identifier: "d2DiagramError")
            .firstMatch
        XCTAssertTrue(errorBanner.waitForExistence(timeout: 20))
    }

    func testAGraphvizFenceRendersAsADiagramImageInTheLivePreview() {
        let text = "# Title\n\n```dot\ndigraph { a -> b; }\n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let diagramImage = context.app.descendants(matching: .any)
            .matching(identifier: "graphvizDiagramImage")
            .firstMatch
        XCTAssertTrue(diagramImage.waitForExistence(timeout: 20))

        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "graphvizDiagramLoading")
            .firstMatch.exists)
        XCTAssertFalse(context.app.descendants(matching: .any).matching(identifier: "graphvizDiagramError")
            .firstMatch.exists)
    }

    func testAMalformedGraphvizFenceShowsAnInlineErrorInTheLivePreview() {
        let text = "```dot\ndigraph { a -> \n```\n"
        let context = makeApp(fixtureContents: text)
        defer {
            context.app.terminate()
            cleanup(context)
        }

        context.app.launch()
        context.app.activate()
        XCTAssertTrue(context.app.windows.firstMatch.waitForExistence(timeout: 5))

        let errorBanner = context.app.descendants(matching: .any)
            .matching(identifier: "graphvizDiagramError")
            .firstMatch
        XCTAssertTrue(errorBanner.waitForExistence(timeout: 20))
    }
}
