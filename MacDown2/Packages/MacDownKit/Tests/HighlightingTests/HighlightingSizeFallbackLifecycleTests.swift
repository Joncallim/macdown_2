import AppKit
import EditorCore
@testable import Highlighting
import Testing
import Themes

/// Register row H5: the size fallback across the highlighter's lifecycle —
/// theme/font, language changes, reload, IME, teardown, the store (tab
/// close/reopen) and several documents at once.
@MainActor
@Suite(.serialized)
struct HighlightingSizeFallbackLifecycleTests {
    private typealias Fixtures = SizeFallbackFixtures
    private let cutoff = SizeFallbackFixtures.policy.reduceAboveUTF16Units

    @Test func themeAndFontChangesWhileReducedKeepItPlainAndUsable() async {
        let editor = Fixtures.editor(units: cutoff + 100)
        editor.highlighter.applyTheme(BundledThemes.dark)
        editor.highlighter.applyFont(NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
        editor.highlighter.invalidateAll()
        await editor.settle()
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(editor.textView.textColor == BundledThemes.dark.chrome.foreground.nsColor)
        #expect(editor.textView.backgroundColor == BundledThemes.dark.chrome.background.nsColor)
        #expect(editor.textView.insertionPointColor == BundledThemes.dark.chrome.caret.nsColor)
        #expect(editor.isPlain)
        #expect(editor.highlighter.styledTokenCount == 0)
    }

    @Test func languageChangesReevaluateTheModeWithoutBuildingForAnOversizedDocument() async {
        let editor = Fixtures.editor(units: cutoff + 100)
        editor.highlighter.setLanguage(nil)
        #expect(editor.highlighter.state == HighlightingState(requestedLanguageID: nil, mode: .plain))
        // Save As into Markdown with an oversized document: no parser built.
        editor.highlighter.setLanguage("markdown")
        #expect(editor.highlighter.state == HighlightingState(
            requestedLanguageID: "markdown",
            mode: .reducedForTestPolicy
        ))
        #expect(editor.highlighter.generation == 0)
        // A language without a size policy highlights at any size.
        editor.highlighter.setLanguage("json")
        #expect(editor.mode == .full)
        #expect(editor.neonIsAttached)
        editor.highlighter.setLanguage("markdown")
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(!editor.neonIsAttached)
        await editor.settle()
        #expect(editor.isPlain, "the JSON highlighter's styles were cleared")
    }

    @Test func anExternalReloadPastTheCutoffIsWithheldAndAShorterOneRestores() async {
        let system = EditorTextSystem(
            identity: "reload",
            initialText: Fixtures.markdown(units: 3000),
            configuration: .default
        )
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: GrammarRegistry(), sizePolicy: Fixtures.markdownOnly
        )
        #expect(highlighter.state.mode == .full)
        let large = Fixtures.markdown(units: cutoff * 2)
        system.replaceTextFromExternal(large, preserving: system.viewportSnapshot(), clearUndo: true)
        #expect(highlighter.state.mode == .reducedForTestPolicy)
        #expect(highlighter.gate.forwardedCharacterEditCount == 0)
        #expect(system.text == large)

        system.setText(Fixtures.markdown(units: 2000))
        for _ in 0 ..< 300 where highlighter.state.mode != .full {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(highlighter.state.mode == .full)
        highlighter.tearDown()
    }

    @Test func aCrossingDuringIMECompositionKeepsTheMarkedText() async {
        let editor = Fixtures.editor(units: cutoff - 1)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        editor.textView.setSelectedRange(NSRange(location: 20, length: 0))
        editor.textView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(
            location: NSNotFound, length: 0
        ))
        #expect(editor.mode == .reducedForTestPolicy)
        await editor.settle()
        #expect(editor.textView.hasMarkedText())
        #expect(editor.textView.markedRange() == NSRange(location: 20, length: 2))
        editor.textView.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!editor.textView.hasMarkedText())
        #expect((editor.textView.string as NSString).substring(with: NSRange(location: 20, length: 2)) == "仮名")
        await editor.settle()
        #expect(editor.isPlain)
    }

    @Test func teardownLeavesPlainPresentationAndIntactContentUndoSelectionAndDelegate() async throws {
        let system = EditorTextSystem(
            identity: "teardown",
            initialText: Fixtures.markdown(units: 4000),
            configuration: .default
        )
        let storage = try #require(system.textView.textStorage)
        #expect(storage.delegate == nil)
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: GrammarRegistry(), sizePolicy: Fixtures.markdownOnly
        )
        try? await Task.sleep(for: .seconds(1))
        system.textView.insertText("typed", replacementRange: NSRange(location: 30, length: 0))
        system.textView.breakUndoCoalescing()
        system.textView.setSelectedRange(NSRange(location: 40, length: 12))
        let text = system.text
        try? await Task.sleep(for: .milliseconds(300))

        highlighter.tearDown()
        #expect(storage.delegate == nil, "the delegate slot is handed back")
        #expect(system.text == text)
        #expect(system.textView.selectedRange() == NSRange(location: 40, length: 12))
        let probe = HighlightedEditorProbe(textView: system.textView)
        #expect(probe.isPlain)
        system.textView.insertText("more", replacementRange: NSRange(location: 0, length: 0))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(probe.isPlain, "a torn-down highlighter styles nothing")
        #expect(system.undoManager.canUndo)
        system.undoManager.undo()
        system.undoManager.undo()
        #expect(system.text == Fixtures.markdown(units: 4000))
    }

    @Test func theStoreReportsStatesAndHandlesTabCloseAndReopen() {
        let store = SyntaxHighlightStore()
        let limit = HighlightingSizePolicy.markdown.reduceAboveUTF16Units
        let large = EditorTextSystem(
            identity: "large",
            initialText: Fixtures.markdown(units: limit + 1),
            configuration: .default
        )
        let small = EditorTextSystem(
            identity: "small",
            initialText: Fixtures.markdown(units: 3000),
            configuration: .default
        )
        _ = store.highlighter(for: "large", textSystem: large, languageID: "markdown", theme: BundledThemes.light)
        _ = store.highlighter(for: "small", textSystem: small, languageID: "markdown", theme: BundledThemes.light)
        #expect(store.state(for: "large")?.mode == .reduced(.documentTooLarge(limitUTF16Units: limit)))
        #expect(store.state(for: "small")?.mode == .full)

        // Growth in one document does not affect the other.
        small.textView.insertText(Fixtures.markdown(units: limit), replacementRange: NSRange(location: 0, length: 0))
        #expect(store.state(for: "small")?.isReduced == true)
        #expect(store.states.count == 2)

        store.evict("large")
        #expect(store.state(for: "large") == nil)
        #expect(large.textView.textStorage?.delegate == nil)
        // Reopen: a new highlighter for the same text system is reduced again.
        _ = store.highlighter(for: "large", textSystem: large, languageID: "markdown", theme: BundledThemes.light)
        #expect(store.state(for: "large")?.isReduced == true)
        store.evictAll()
        #expect(store.states.isEmpty)
    }
}

/// Reads rendering attributes from a bare text view (no `HighlightedEditor`).
@MainActor
struct HighlightedEditorProbe {
    let textView: NSTextView

    var isPlain: Bool {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return true }
        var plain = true
        let origin = contentManager.documentRange.location
        layoutManager.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, _ in
            if !RenderedRun.signature(of: attributes).isEmpty {
                plain = false
            }
            return plain
        }
        return plain
    }
}
