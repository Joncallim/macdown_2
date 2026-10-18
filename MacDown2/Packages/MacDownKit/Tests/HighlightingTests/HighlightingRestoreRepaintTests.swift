import AppKit
@testable import Highlighting
import Testing

/// Found by a native Pinyin session on the Debug app: after a document left reduced mode (the note disappeared) it
/// stayed
/// visually uncoloured until the next edit, although TextKit held the rendering attributes (logged: four coloured runs,
/// 12
/// styled tokens, yet plain text on screen). The harness has no display, so these tests pin the mechanism that fixes
/// it:
/// a repaint is requested after the restore's styling pass, and that repaint changes nothing but the redraw.
@MainActor
@Suite(.serialized)
struct HighlightingRestoreRepaintTests {
    private typealias Fixtures = SizeFallbackFixtures
    private let cutoff = SizeFallbackFixtures.policy.reduceAboveUTF16Units
    private let small = "# Hi\n\nsome *emphasis* and `code` and **bold**\n"

    private func hosted(_ editor: HighlightedEditor) -> NSWindow {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = editor.textView
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func reducedEditor() async -> HighlightedEditor {
        let editor = Fixtures.editor(units: cutoff - 100)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        editor.insert(Fixtures.markdown(units: 2000), at: 50) // crosses: reduced, plain
        await editor.settle(.seconds(1))
        #expect(editor.mode == .reducedForTestPolicy)
        return editor
    }

    @Test func aRestoreColoursTheDocumentAndRequestsARepaint() async {
        let editor = await reducedEditor()
        let window = hosted(editor)
        defer { window.orderOut(nil) }
        #expect(editor.highlighter.repaintCount == 0)

        editor.textView.insertText(small, replacementRange: NSRange(location: 0, length: editor.length))
        await editor.settle(.seconds(3)) // idle delay (200 ms in the test policy) plus time to style

        #expect(editor.mode == .full)
        #expect(!editor.isPlain)
        #expect(editor.highlighter.repaintCount >= 1, "no repaint was requested after the restore's styling pass")
    }

    @Test func theRepaintChangesNeitherTheTextNorUndoNorWhatNeonHears() async {
        let editor = await reducedEditor()
        let window = hosted(editor)
        defer { window.orderOut(nil) }
        editor.textView.insertText(small, replacementRange: NSRange(location: 0, length: editor.length))
        editor.textView.breakUndoCoalescing()
        let text = editor.textView.string
        let canUndo = editor.system.undoManager.canUndo
        await editor.settle(.milliseconds(400)) // restore not yet due: still reduced
        let edits = editor.highlighter.gate.characterEditCount

        await editor.settle(.seconds(3))
        #expect(editor.mode == .full)
        #expect(editor.highlighter.repaintCount >= 1)
        #expect(editor.textView.string == text)
        #expect(editor.system.undoManager.canUndo == canUndo)
        #expect(editor.highlighter.gate.characterEditCount == edits, "the repaint is not a character edit")
    }

    @Test func noRepaintIsRequestedOutsideTheRestoreWindow() async {
        let editor = Fixtures.editor(units: 3000)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        editor.insert("typing", at: 10)
        await editor.settle(.seconds(1))
        #expect(editor.highlighter.repaintCount == 0, "ordinary typing must not pay for a repaint")
    }
}
