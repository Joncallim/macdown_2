import XCTest

/// Native corroboration of the IME / dead-key composition fixes (#436, #439, #443). The package and app-target tests
/// drive `setMarkedText`/`insertText` directly; these run real synthesized key events through the live app's text
/// input system. On a US/ABC keyboard layout ⌥E opens a dead-key composition (marked text "´") and the next "e"
/// commits "é" — the same marked-text lifecycle an input method uses, without changing any system setting.
/// The tests assume the US/ABC layout (the default of this project's development machines).
@MainActor
final class DeadKeyCompositionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!
    private var fixture: URL!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()

        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        fixture = fixturesDir.appendingPathComponent("a.md")
        try? "start\n".write(to: fixture, atomically: true, encoding: .utf8)

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = ["-UITesting", "-sessionDir", sessionDir.path, "-openFiles", fixture.path]
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    private func launchAndFocusEditor() -> XCUIElement {
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        // Caret to the end of the document.
        app.typeKey(.downArrow, modifierFlags: .command)
        return textView
    }

    private func commitAcuteE(in textView: XCUIElement) {
        textView.typeKey("e", modifierFlags: .option) // dead key: opens the composition
        textView.typeText("e") // commits "é"
    }

    private func waitForValue(of textView: XCUIElement, where predicate: @escaping (String) -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate(textView.value as? String ?? "") },
            object: nil
        )
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    func testDeadKeyCompositionCommitsAnAccentedCharacter() {
        let textView = launchAndFocusEditor()

        commitAcuteE(in: textView)

        XCTAssertTrue(waitForValue(of: textView) { $0.contains("é") }, "value: \(textView.value ?? "nil")")
    }

    /// #439: after an undo the editor's record of the agreed text was stale, so the next composition's commit was
    /// discarded.
    func testDeadKeyCompositionStillCommitsAfterAnUndo() {
        let textView = launchAndFocusEditor()
        textView.typeText("abc")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: textView) { !$0.contains("abc") }, "the undo must remove the typed text")

        commitAcuteE(in: textView)

        XCTAssertTrue(waitForValue(of: textView) { $0.contains("é") }, "value: \(textView.value ?? "nil")")
    }

    /// #436/#443: a model replacement (clean external reload) arriving while a composition is open must not be
    /// reverted by the commit.
    func testAnExternalReloadDuringAnOpenCompositionIsNotReverted() throws {
        let textView = launchAndFocusEditor()

        textView.typeKey("e", modifierFlags: .option) // composition open (marked "´"), document still clean
        try "EXTERNAL VERSION\n".write(to: fixture, atomically: true, encoding: .utf8)
        XCTAssertTrue(
            waitForValue(of: textView) { $0.contains("EXTERNAL VERSION") },
            "the clean document must reload; value: \(textView.value ?? "nil")"
        )
        textView.typeText("e")

        // The reload clears the open composition, so the "e" lands as a plain letter at the preserved caret INSIDE
        // the reloaded text ("EXTERNAeL VERSION"): the reload must survive and the old text must not come back.
        XCTAssertTrue(
            waitForValue(of: textView) { $0.contains("VERSION") && $0.contains("EXTERN") && !$0.contains("start") },
            "the commit must not revert the reload; value: \(textView.value ?? "nil")"
        )
    }
}
