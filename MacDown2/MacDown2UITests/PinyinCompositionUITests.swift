import Carbon
import XCTest

/// Native corroboration with a real CJK input method: macOS Simplified Chinese – Pinyin
/// (`com.apple.inputmethod.SCIM.ITABC`).
/// The tests switch the active input source to Pinyin for their own duration and restore the previously selected source
/// afterwards. If Pinyin is not enabled, they skip (and the skip must be recorded, not read as a pass).
/// Scope: Simplified Pinyin only. This does not cover other CJK input methods, Japanese or Korean engines, or the
/// candidate-window UI itself; the candidate is chosen with the keyboard (space / digit).
@MainActor
final class PinyinCompositionUITests: XCTestCase {
    private static let pinyinID = "com.apple.inputmethod.SCIM.ITABC"
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!
    private var fixture: URL!
    private var previousSourceID: String?

    private static func sourceID(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func currentSourceID() -> String? {
        sourceID(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    private static func select(_ id: String) -> Bool {
        guard let all = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource],
              let source = all.first(where: { sourceID(of: $0) == id }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        previousSourceID = Self.currentSourceID()
        guard Self.select(Self.pinyinID) else {
            throw XCTSkip("Simplified Pinyin is not enabled; enable it in System Settings > Keyboard > Input Sources")
        }
        // Selection is asynchronous; wait until the system reports it.
        let deadline = Date().addingTimeInterval(5)
        while Self.currentSourceID() != Self.pinyinID, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try XCTSkipUnless(Self.currentSourceID() == Self.pinyinID, "could not switch to Pinyin")

        app = XCUIApplication()
        fixturesDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        fixture = fixturesDir.appendingPathComponent("a.md")
        try "start\n".write(to: fixture, atomically: true, encoding: .utf8)
        sessionDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        app.launchArguments = ["-UITesting", "-sessionDir", sessionDir.path, "-openFiles", fixture.path]
    }

    override func tearDown() {
        app?.terminate()
        if let previous = previousSourceID {
            _ = Self.select(previous)
        }
        try? sessionDir.map(FileManager.default.removeItem(at:))
        try? fixturesDir.map(FileManager.default.removeItem(at:))
    }

    private func launchAndFocusEditor(text: String? = nil) throws -> XCUIElement {
        if let text {
            try text.write(to: fixture, atomically: true, encoding: .utf8)
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        return textView
    }

    private func value(of textView: XCUIElement) -> String {
        textView.value as? String ?? ""
    }

    private func wait(_ textView: XCUIElement, timeout: TimeInterval = 10,
                      _ predicate: @escaping (String) -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate(textView.value as? String ?? "") },
            object: nil
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Types pinyin and commits the first candidate with space.
    private func compose(_ pinyin: String, in textView: XCUIElement) {
        textView.typeText(pinyin)
        textView.typeText(" ")
    }

    func testPinyinCompositionCommitsAChineseCandidate() throws {
        let textView = try launchAndFocusEditor()
        compose("nihao", in: textView)
        XCTAssertTrue(wait(textView) { $0.contains("你好") }, "value: \(value(of: textView))")
        XCTAssertFalse(value(of: textView).contains("nihao"), "the pre-edit letters must be replaced by the candidate")
    }

    func testEscapeCancelsAnOpenCompositionWithoutLeavingPreeditText() throws {
        let textView = try launchAndFocusEditor()
        textView.typeText("nihao")
        textView.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait(textView) { $0 == "start\n" }, "value: \(value(of: textView))")
    }

    func testUndoAndRedoAroundACommittedComposition() throws {
        let textView = try launchAndFocusEditor()
        compose("nihao", in: textView)
        XCTAssertTrue(wait(textView) { $0.contains("你好") })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            wait(textView) { !$0.contains("你好") },
            "undo must remove the committed text; value: \(value(of: textView))"
        )
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(wait(textView) { $0.contains("你好") }, "redo must restore it; value: \(value(of: textView))")
        // A new composition still commits after undo/redo (the stale-model class of bug, #439).
        compose("shijie", in: textView)
        XCTAssertTrue(wait(textView) { $0.contains("世界") }, "value: \(value(of: textView))")
    }

    /// A document 8,190 UTF-16 units long is under the 8,192-unit highlighting cut-off. Opening a Pinyin composition
    /// adds
    /// pre-edit letters to the text storage (marked text), which pushes the document over the cut-off DURING the
    /// composition; committing a candidate then replaces them. Nothing may be lost or reverted, and the reduced-mode
    /// note must appear.
    func testACompositionThatCrossesTheHighlightingCutoffKeepsTheText() throws {
        let line = "some *text* with `code` and a [link](http://example.com)\n"
        var text = "# Title\n\n"
        while text.utf16.count < 8190 {
            text += line
        }
        text = String(text.prefix(8189)) + "\n"
        XCTAssertEqual(text.utf16.count, 8190)
        let textView = try launchAndFocusEditor(text: text)

        textView.typeText("nihaoma") // 7 pre-edit letters: 8,197 units while composing
        textView.typeText(" ") // commit
        XCTAssertTrue(wait(textView) { $0.contains("你好吗") }, "committed text must be present")
        XCTAssertTrue(value(of: textView).hasPrefix("# Title"), "the rest of the document must be intact")
        let phrase = "Syntax highlighting is off"
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@ OR help CONTAINS %@",
            phrase,
            phrase,
            phrase
        )
        let note = app.descendants(matching: .any).matching(predicate)
        XCTAssertTrue(note.firstMatch.waitForExistence(timeout: 10), "the reduced-highlighting note should be shown")

        // Editing continues normally in reduced mode, including undo of the committed composition.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(wait(textView) { !$0.contains("你好吗") }, "undo works in reduced mode")
        compose("zhongwen", in: textView)
        XCTAssertTrue(wait(textView) { $0.contains("中文") }, "composition still commits in reduced mode")
    }
}
