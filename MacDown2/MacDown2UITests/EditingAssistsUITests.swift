import XCTest

/// E10 smoke coverage through the real app: Return-key list continuation in
/// Markdown, and no synthetic pairing in non-Markdown formats.
@MainActor
final class EditingAssistsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()

        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        let markdownFile = fixturesDir.appendingPathComponent("a.md")
        // No trailing newline: the initial caret lands at the end of the
        // single list line, exactly where Return must continue the list.
        try? "- item".write(to: markdownFile, atomically: true, encoding: .utf8)
        let plainFile = fixturesDir.appendingPathComponent("a.txt")
        try? "".write(to: plainFile, atomically: true, encoding: .utf8)

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", "\(markdownFile.path),\(plainFile.path)",
        ]
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    /// Selects the given native tab through the app's own Window menu (the
    /// established pattern for deterministic tab activation; with several
    /// files opened at launch the initially selected tab is not guaranteed).
    private func selectTab(_ index: Int) {
        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuBarItems["Window"].menuItems["Select Tab \(index)"].firstMatch.click()
    }

    func testListContinuationOnReturn() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(1)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()

        // The fixture is "- item" and the caret is at its end; pressing
        // Return must continue the unordered list.
        app.typeKey(.return, modifierFlags: [])

        let expected = "- item\n- "
        let predicate = NSPredicate { _, _ in
            (textView.value as? String)?.hasSuffix(expected) == true
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)

        // Normal input continues after the handled Return.
        textView.typeText("next")
        XCTAssertTrue((textView.value as? String)?.hasSuffix("- next") == true)
    }

    func testNoPairingInPlainText() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let plainTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.txt")).firstMatch
        XCTAssertTrue(plainTab.waitForExistence(timeout: 5))
        selectTab(2)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // E10 must never fire outside Markdown: a typed "(" stays a lone "(".
        textView.click()
        textView.typeText("(")
        let value = textView.value as? String ?? ""
        XCTAssertEqual(value, "(")
    }

    /// The Format menu's Markdown commands must be reachable while the editor
    /// is focused: the menu item enables (first-responder identity) and the
    /// click applies through the same one-edit command bridge as ⌘B.
    func testBoldMenuCommandAppliesToFocusedEditor() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(1)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()

        app.menuBars.menuBarItems["Format"].click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(boldItem.waitForExistence(timeout: 5))
        XCTAssertTrue(boldItem.isEnabled, "Bold must be enabled while the Markdown editor is focused")

        boldItem.click()

        // The fixture is "- item" with the caret at its end; Bold on an empty
        // selection inserts the empty `**` delimiters with the caret inside.
        XCTAssertTrue((textView.value as? String)?.hasSuffix("****") == true)
    }

    /// Command validation follows the real responder chain: moving focus to
    /// the sidebar or Find field disables formatting, and returning to the
    /// editor re-enables it. The action is also guarded independently so a
    /// stale menu update cannot edit the wrong responder.
    func testFormattingMenuTracksEditorSidebarFindAndEditorFocus() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(1)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(boldItem.isEnabled)

        let folderSection = app.otherElements["folderSection"]
        XCTAssertTrue(folderSection.waitForExistence(timeout: 5))
        folderSection.click()
        XCTAssertFalse(boldItem.isEnabled)

        app.typeKey("f", modifierFlags: .command)
        let findField = app.searchFields.firstMatch
        XCTAssertTrue(findField.waitForExistence(timeout: 5))
        XCTAssertFalse(boldItem.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        textView.click()
        XCTAssertTrue(boldItem.isEnabled)
    }

    func testFormattingMenuRefreshesAfterKeyboardTabAndFocusOutline() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(1)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(boldItem.isEnabled)

        // Native tab navigation changes the active editor/responder without
        // generating ordinary typing events.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertFalse(boldItem.isEnabled)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        textView.click()
        XCTAssertTrue(boldItem.isEnabled)

        // Focus Outline is a coordinator-owned programmatic focus transition.
        app.typeKey("o", modifierFlags: [.control, .command])
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"),
            object: boldItem
        )
        XCTAssertEqual(XCTWaiter().wait(for: [focusExpectation], timeout: 2), .completed)
        textView.click()
        XCTAssertTrue(boldItem.isEnabled)
    }
}
