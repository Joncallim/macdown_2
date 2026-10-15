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

    /// Waits (2 s, the bound the Focus Outline step always used) for a menu
    /// item's enablement to reach `enabled`. SwiftUI publishes a command's
    /// `.disabled` state to its `NSMenuItem` on its next update pass, not
    /// synchronously with the focus change: logging showed
    /// `canPerformMarkdownEditingCommand` already `true` while XCUITest still
    /// read the item as disabled, then enabled on the next sample.
    private func waitFor(_ item: XCUIElement, enabled: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)),
            object: item
        )
        return XCTWaiter().wait(for: [expectation], timeout: 2) == .completed
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

    /// EPIC-22 Slice 4a (#140) made structural bracket/quote pairing a
    /// general, every-format assist, so "(" → "()" is now correct in plain
    /// text too. What must still never fire outside Markdown is E10's own
    /// Markdown delimiter pairing (`*`, `_`, backtick).
    func testNoMarkdownDelimiterPairingInPlainText() {
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let plainTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.txt")).firstMatch
        XCTAssertTrue(plainTab.waitForExistence(timeout: 5))
        selectTab(2)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // E10's Markdown delimiters stay lone characters outside Markdown…
        textView.click()
        textView.typeText("*_`")
        XCTAssertEqual(textView.value as? String ?? "", "*_`")

        // …while the general structural pairing still applies here.
        textView.typeText("(")
        XCTAssertEqual(textView.value as? String ?? "", "*_`()")
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
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // A sidebar control that really takes keyboard focus. The folder
        // section's "No folder opened" placeholder this used to click centers
        // on its "Open Folder…" button, which (like any macOS button without
        // Full Keyboard Access) never becomes first responder — the editor
        // kept focus, so Bold correctly stayed enabled.
        let sidebarSearchField = app.textFields["folderSearchField"]
        XCTAssertTrue(sidebarSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarSearchField.isHittable, "Sidebar focus target must be interactable")
        sidebarSearchField.click()
        XCTAssertTrue(waitFor(boldItem, enabled: false))

        // Back to the editor first, so the Find step below proves its own
        // transition rather than inheriting the sidebar's disabled state.
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // The app's own Find in Document bar (EPIC-22 Slice 5a; ⌘F). Not
        // `app.searchFields.firstMatch`: that only ever matched the Help menu's always-present search field.
        app.typeKey("f", modifierFlags: .command)
        let findField = app.textFields["findBarQueryField"]
        XCTAssertTrue(findField.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        // The bar really took keyboard focus: typing goes to its query, not
        // into the document.
        app.typeText("zz")
        XCTAssertEqual(findField.value as? String, "zz")
        XCTAssertEqual(textView.value as? String, "- item")
        app.typeKey(.escape, modifierFlags: [])

        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))
    }

    /// The standard ⌘F opens the docked Find in Document bar and focuses its query field (owner decision: it used to
    /// do nothing in the editor).
    func testCommandFOpensTheFindBar() {
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        selectTab(1)
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let findField = app.textFields["findBarQueryField"]

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 5), "⌘F must open the Find bar")
        app.typeText("zz")
        XCTAssertEqual(findField.value as? String, "zz", "the bar took keyboard focus")
        XCTAssertEqual(textView.value as? String, "- item", "typing did not reach the document")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(findField), "Escape closes the bar")
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // Native tab navigation changes the active editor/responder without
        // generating ordinary typing events.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // Focus Outline is a coordinator-owned programmatic focus transition.
        app.typeKey("o", modifierFlags: [.control, .command])
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))
    }
}
