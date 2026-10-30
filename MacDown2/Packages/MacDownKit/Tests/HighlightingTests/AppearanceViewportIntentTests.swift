import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

@MainActor
@Suite("Appearance viewport interaction ownership", .serialized)
struct AppearanceViewportIntentTests {
    enum Intent: CaseIterable, Sendable {
        case scroll, liveScroll, ongoingLiveScroll, edit, selection, detach
    }

    @Test(arguments: Intent.allCases)
    func aLaterInteractionSupersedesThePendingThemeRestore(_ intent: Intent) async throws {
        let fixture = try MountedAppearanceEditor()
        defer { fixture.close() }
        try await fixture.positionNearEnd()
        let system = fixture.system
        let oldSelection = system.textView.selectedRanges
        fixture.highlighter.applyTheme(BundledThemes.light)
        try #require(system.presentationViewport != nil)
        switch intent {
        case .scroll:
            system.scrollOffset = 0
        case .liveScroll:
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: fixture.scroll)
            fixture.scroll.contentView.scroll(to: .zero)
        case .ongoingLiveScroll:
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: fixture.scroll)
            fixture.scroll.contentView.scroll(to: .zero)
        case .edit:
            system.setText(fixture.source + " edit")
            system.textView.selectedRanges = oldSelection
            fixture.scroll.contentView.scroll(to: .zero)
        case .selection:
            system.selectedRange = NSRange(location: 0, length: 0)
            fixture.scroll.contentView.scroll(to: .zero)
        case .detach:
            fixture.window.contentView = nil
        }
        system.restorePresentationViewportIfNeeded()
        #expect(system.presentationViewport == nil)
        try await fixture.settle()
        #expect(system.presentationViewport == nil)
        if intent != .detach {
            #expect(abs(fixture.scroll.contentView.bounds.minY) <= 1)
        }
        if intent == .edit {
            #expect(system.text == fixture.source + " edit")
        }
        if intent == .selection {
            #expect(system.selectedRange == NSRange(location: 0, length: 0))
        }
    }

    @Test func rapidThemeChangesKeepTheOriginalLogicalRowAndSelection() async throws {
        let fixture = try MountedAppearanceEditor()
        defer { fixture.close() }
        try await fixture.positionNearEnd()
        let before = fixture.system.viewportSnapshot()
        for _ in 0 ..< 8 {
            fixture.highlighter.applyTheme(BundledThemes.light)
            fixture.hosting.layoutSubtreeIfNeeded()
            fixture.hosting.displayIfNeeded()
            try expectSameRow(before, fixture.system.viewportSnapshot())
            await Task.yield()
            fixture.highlighter.applyTheme(BundledThemes.dark)
            fixture.hosting.layoutSubtreeIfNeeded()
            fixture.hosting.displayIfNeeded()
            try expectSameRow(before, fixture.system.viewportSnapshot())
        }
        fixture.highlighter.applyTheme(BundledThemes.light)
        #expect(fixture.system.textView.backgroundColor.isEqual(BundledThemes.light.chrome.background.nsColor))
        try await fixture.settle()
        try expectSameRow(before, fixture.system.viewportSnapshot())
        #expect(fixture.system.presentationViewport == nil)
    }

    @Test func themeChangesPreserveAPartiallyVisibleWrappedRow() async throws {
        let source = "prefix\n\n" + String(repeating: "wrapped segment **word** ", count: 300)
            + "\n\n" + String(repeating: "following paragraph\n\n", count: 100)
        let fixture = try MountedAppearanceEditor(source: source, width: 330)
        defer { fixture.close() }
        try await fixture.settle()
        fixture.system.revealSelection(utf16Range: NSRange(location: 2500, length: 3), flash: false)
        try await fixture.settle()
        let frame = try #require(fixture.system.layoutFragmentFrame(atUTF16Location: 8))
        fixture.system.scrollOffset = frame.minY + fixture.system.textView.textContainerInset.height + 237.25
        try await fixture.settle()
        let before = fixture.system.viewportSnapshot()
        try #require((before.topVisibleFragmentOffset ?? 0) > 100, "Exercise a later wrapped row, not its first row")
        for theme in [BundledThemes.light, BundledThemes.dark, BundledThemes.light] {
            fixture.highlighter.applyTheme(theme)
            #expect(fixture.system.textView.backgroundColor.isEqual(theme.chrome.background.nsColor))
            try await fixture.settle()
            try expectSameRow(before, fixture.system.viewportSnapshot())
        }
    }

    @Test func aThemeChangeDoesNotReplaceAnActiveComposition() async throws {
        let fixture = try MountedAppearanceEditor()
        defer { fixture.close() }
        try await fixture.positionNearEnd()
        fixture.system.textView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0),
                                              replacementRange: fixture.system.selectedRange)
        let marked = fixture.system.textView.markedRange()
        let selected = fixture.system.textView.selectedRanges
        let source = fixture.system.text
        fixture.highlighter.applyTheme(BundledThemes.light)
        try await fixture.settle()
        #expect(fixture.system.textView.hasMarkedText())
        #expect(fixture.system.textView.markedRange() == marked)
        #expect(fixture.system.textView.selectedRanges == selected)
        #expect(fixture.system.text == source)
        fixture.system.textView.unmarkText()
    }

    @Test func anotherMarkedTextUpdateCancelsTheOlderThemeRestore() async throws {
        let fixture = try MountedAppearanceEditor()
        defer { fixture.close() }
        try await fixture.positionNearEnd()
        fixture.system.textView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0),
                                              replacementRange: fixture.system.selectedRange)
        fixture.highlighter.applyTheme(BundledThemes.light)
        try #require(fixture.system.presentationViewport != nil)
        let oldMarkedRange = fixture.system.textView.markedRange()
        fixture.system.textView.setMarkedText("かに", selectedRange: NSRange(location: 2, length: 0),
                                              replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.system.textView.markedRange() == oldMarkedRange)
        #expect(fixture.system.presentationViewport == nil, "An equal-length IME edit is still new user intent")
        try await fixture.settle()
        #expect(fixture.system.textView.hasMarkedText())
        fixture.system.textView.unmarkText()
    }

    @Test func aFullMarkdownHighlighterKeepsTheLogicalViewport() async throws {
        let source = (1 ... 45).map {
            "Paragraph \($0): **bold text** with `code` and *emphasis* for a wrapped highlighter control."
        }.joined(separator: "\n\n")
        let fixture = try MountedAppearanceEditor(source: source, width: 400, language: "markdown")
        defer { fixture.close() }
        try await fixture.settle()
        try #require(fixture.highlighter.state.mode == .full)
        try #require(fixture.highlighter.styledTokenCount > 0)
        let location = (source as NSString).range(of: "Paragraph 35:").location
        fixture.system.revealSelection(utf16Range: NSRange(location: location, length: 3), flash: false)
        try await fixture.settle()
        fixture.system.scrollOffset = (fixture.system.textView.frame.height - 500) * 0.7
        try await fixture.settle()
        let before = fixture.system.viewportSnapshot()
        try #require((before.topVisibleUTF16Offset ?? 0) > 500)
        for theme in [BundledThemes.light, BundledThemes.dark, BundledThemes.light] {
            let tokens = fixture.highlighter.styledTokenCount
            fixture.highlighter.applyTheme(theme)
            #expect(fixture.system.textView.backgroundColor.isEqual(theme.chrome.background.nsColor))
            try await fixture.settle()
            #expect(fixture.highlighter.styledTokenCount > tokens, "Neon must acknowledge the changed theme")
            try expectSameRow(before, fixture.system.viewportSnapshot())
        }
    }

    @Test func aPendingExternalReplacementKeepsItsViewportAuthority() async throws {
        let fixture = try MountedAppearanceEditor()
        defer { fixture.close() }
        try await fixture.positionNearEnd()
        let snapshot = fixture.system.viewportSnapshot()
        fixture.system.replaceTextFromExternal(fixture.source, preserving: snapshot, clearUndo: false)
        try #require(fixture.system.pendingScrollOffset != nil)
        fixture.highlighter.applyTheme(BundledThemes.light)
        #expect(fixture.system.presentationViewport == nil)
        try await fixture.settle()
        #expect(fixture.system.presentationViewport == nil)
        #expect(fixture.system.text == fixture.source)
    }

    private func expectSameRow(_ before: EditorViewportSnapshot, _ after: EditorViewportSnapshot) throws {
        #expect(after.selectedRange == before.selectedRange)
        #expect(after.topVisibleUTF16Offset == before.topVisibleUTF16Offset)
        let oldRow = try #require(before.topVisibleFragmentOffset)
        let newRow = try #require(after.topVisibleFragmentOffset)
        #expect(abs(newRow - oldRow) <= 1, "A wrapped row must not snap to its paragraph's first row")
    }
}

@MainActor
private final class MountedAppearanceEditor {
    let source: String
    let system: EditorTextSystem
    let highlighter: NeonSyntaxHighlighter
    let scroll: NSScrollView
    let hosting: NSHostingView<EditorView>
    let window: NSWindow
    private let store = EditorTextSystemStore()

    init(source: String = AppearanceViewportTests.source, width: CGFloat = 620, language: String? = nil) throws {
        self.source = source
        let identity = UUID().uuidString
        hosting = NSHostingView(rootView: EditorView(
            text: .constant(source), identity: identity, configuration: .default, store: store
        ))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        system = try #require(store.existingSystem(for: identity))
        scroll = try #require(system.textView.enclosingScrollView)
        highlighter = NeonSyntaxHighlighter(textSystem: system, languageID: language,
                                            theme: BundledThemes.dark, registry: GrammarRegistry())
    }

    func settle() async throws {
        for _ in 0 ..< 30 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func positionNearEnd() async throws {
        try await settle()
        let range = (source as NSString).range(of: "Paragraph 480:")
        try #require(range.location != NSNotFound)
        system.revealSelection(utf16Range: NSRange(location: range.location, length: 3), flash: false)
        try await settle()
        system.scrollOffset = max(0, (system.textView.frame.height - scroll.contentView.bounds.height) * 0.96)
        try await settle()
        try #require(system.topVisibleUTF16Offset > (source as NSString).range(of: "Paragraph 400:").location)
    }

    func close() {
        highlighter.tearDown()
        window.contentView = nil
        window.close()
        store.evictAll()
    }
}
