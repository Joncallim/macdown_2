import AppKit
import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

@MainActor
@Suite("Mounted editor appearance viewport", .serialized)
struct AppearanceViewportTests {
    enum Probe: Sendable {
        case plain, markdown, background

        @MainActor
        func apply(_ theme: Theme, to system: EditorTextSystem, highlighter: NeonSyntaxHighlighter) {
            switch self {
            case .plain, .markdown: highlighter.applyTheme(theme)
            case .background: system.textView.backgroundColor = theme.chrome.background.nsColor
            }
        }
    }

    @Test(arguments: [Probe.plain, .markdown, .background])
    func themeChangesKeepTheSourceViewport(probe: Probe) async throws {
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let hosting = NSHostingView(rootView: EditorView(
            text: .constant(Self.source), identity: identity, configuration: .default, store: store
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderBack(nil)
        defer {
            window.contentView = nil
            window.close()
            store.evictAll()
        }
        hosting.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        let trace = AppearanceGeometryTrace(system: system, scroll: scroll, mode: String(describing: probe))
        defer { trace.stop() }
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: probe == .markdown ? "markdown" : nil,
            theme: BundledThemes.dark, registry: GrammarRegistry()
        )
        defer { highlighter.tearDown() }
        try await position(system, scroll: scroll, highlighter: highlighter, hosting: hosting)
        try await checkNoChange(system, scroll: scroll, trace: trace, highlighter: highlighter, hosting: hosting)
        for (index, theme) in [BundledThemes.light, BundledThemes.dark, BundledThemes.light].enumerated() {
            try await check(theme, index: index, probe: probe, context: Context(
                system: system, scroll: scroll, trace: trace, highlighter: highlighter, hosting: hosting
            ))
        }
    }

    private func position(_ system: EditorTextSystem, scroll: NSScrollView,
                          highlighter: NeonSyntaxHighlighter, hosting: NSView) async throws {
        try #require(Self.source.utf8.count == 35307)
        try await settle(highlighter, hosting: hosting, needsActivity: highlighter.state.mode == .full, after: 0)
        let range = (Self.source as NSString).range(of: "Paragraph 480:")
        try #require(range.location != NSNotFound)
        system.revealSelection(utf16Range: NSRange(location: range.location, length: 0), flash: false)
        try await settle(highlighter, hosting: hosting, needsActivity: false, after: 0)
        // Reveal schedules a frame correction. One ordinary scroll then establishes the measured control.
        let targetY = max(0, (system.textView.frame.height - scroll.contentView.bounds.height) * 0.96)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: targetY))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(highlighter, hosting: hosting, needsActivity: false, after: 0)
        try #require(system.topVisibleUTF16Offset > (Self.source as NSString).range(of: "Paragraph 400:").location,
                     "The near-end viewport control must be established before testing a theme")
    }

    private func checkNoChange(_ system: EditorTextSystem, scroll: NSScrollView, trace: AppearanceGeometryTrace,
                               highlighter: NeonSyntaxHighlighter, hosting: NSView) async throws {
        let beforeY = scroll.contentView.bounds.minY
        let beforeAnchor = system.topVisibleUTF16Offset
        trace.begin("noThemeChange")
        trace.record("before.sham")
        try await settle(highlighter, hosting: hosting, needsActivity: false, after: 0)
        trace.record("after.sham.beforeAnchorQuery")
        let finalAnchor = system.topVisibleUTF16Offset
        trace.record("after.sham.anchorQuery")
        try #require(abs(finalAnchor - beforeAnchor) < 150, "The no-change control must keep its source anchor")
        try #require(abs(trace.minimumY - beforeY) <= 1, "The no-change control must keep its clip offset")
    }

    private struct Context {
        let system: EditorTextSystem
        let scroll: NSScrollView
        let trace: AppearanceGeometryTrace
        let highlighter: NeonSyntaxHighlighter
        let hosting: NSView
    }

    private func check(_ theme: Theme, index: Int, probe: Probe, context: Context) async throws {
        let system = context.system
        let scroll = context.scroll
        let trace = context.trace
        let highlighter = context.highlighter
        let hosting = context.hosting
        let beforeAnchor = system.topVisibleUTF16Offset
        let beforeSnapshot = system.viewportSnapshot()
        let previousColor = system.textView.backgroundColor
        let selection = system.selectedRange
        let revision = system.contentRevision
        let tokens = highlighter.styledTokenCount
        trace.begin("theme.\(index)")
        trace.record("before.apply")
        probe.apply(theme, to: system, highlighter: highlighter)
        trace.record("after.apply.beforeLayoutQuery")
        try #require(!previousColor.isEqual(theme.chrome.background.nsColor), "Theme must actually differ")
        try #require(system.textView.backgroundColor.isEqual(theme.chrome.background.nsColor))
        if probe != .background {
            try #require(system.textView.textColor?.isEqual(theme.chrome.foreground.nsColor) == true)
        }
        trace.record("chrome.acknowledged")
        try await settle(highlighter, hosting: hosting, needsActivity: highlighter.state.mode == .full, after: tokens)
        trace.record("styling.settled.beforeAnchorQuery")
        let finalAnchor = system.topVisibleUTF16Offset
        trace.record("after.anchorQuery")
        #expect(system.text == Self.source)
        #expect(system.contentRevision == revision)
        #expect(system.selectedRange == selection)
        let afterSnapshot = system.viewportSnapshot()
        #expect(finalAnchor == beforeAnchor,
                "Theme \(index) moved logical source anchor \(beforeAnchor) to \(finalAnchor)")
        let beforeRow = try #require(beforeSnapshot.topVisibleFragmentOffset)
        let afterRow = try #require(afterSnapshot.topVisibleFragmentOffset)
        #expect(abs(afterRow - beforeRow) <= 1, "Theme must preserve the precise wrapped-row position")
    }

    private func settle(_ highlighter: NeonSyntaxHighlighter, hosting: NSView,
                        needsActivity: Bool, after baseline: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var lastCount = highlighter.styledTokenCount
        var lastChange = ContinuousClock.now
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let count = highlighter.styledTokenCount
            if count != lastCount {
                lastCount = count
                lastChange = .now
            }
            if !needsActivity || count > baseline, ContinuousClock.now - lastChange > .milliseconds(200) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("APPEARANCE_STYLING mode=\(highlighter.state.mode) tokens=\(highlighter.styledTokenCount) "
            + "requests=\(highlighter.liveLayerRequestCount)")
        Issue.record("Appearance styling did not acknowledge and settle within five seconds")
        throw CancellationError()
    }

    static var source: String {
        let header = "# SIGNED_A_SAVED_SOURCE\n\n\n\n"
        let images = [
            "SAFE_LOCAL](assets/blue.png", "SAFE_SYMLINK](safe-link.png",
            "ESCAPE_RED](escape-link.png", "SIBLING_GREEN_DENIED](sibling-link.png",
            "NESTED_BLUE](nested/asset.png", "OUTSIDE_RED](../outside.png",
        ]
        .map { "![" + $0 + ")\n\n\n\n" }.joined()
        let paragraphs = (1 ... 500).map { index in
            let image = switch index {
            case 240: "![MID_LOCAL](assets/blue.png)\n\n"
            case 480: "![END_LOCAL](assets/blue.png)\n\n"
            default: ""
            }
            let text = index == 480 ? "dxyisposable" : "disposable"
            return image + String(format: "Paragraph %03d: \(text) native source for bounded scroll and edit.", index)
        }.joined(separator: "\n\n")
        return header + images + paragraphs + "\n"
    }
}

/// Raw frame/clip observations deliberately do not ask TextKit to lay out or resolve an anchor.
@MainActor
private final class AppearanceGeometryTrace {
    private let system: EditorTextSystem
    private let scroll: NSScrollView
    private let mode: String
    private var observers: [NSObjectProtocol] = []
    private var phase = "setup"
    private var observations = 0
    private(set) var minimumY: CGFloat = .greatestFiniteMagnitude

    init(system: EditorTextSystem, scroll: NSScrollView, mode: String) {
        self.system = system
        self.scroll = scroll
        self.mode = mode
        scroll.contentView.postsBoundsChangedNotifications = true
        system.textView.postsFrameChangedNotifications = true
        for (name, object, event) in [
            (NSView.boundsDidChangeNotification, scroll.contentView as NSView, "clip.notification"),
            (NSView.frameDidChangeNotification, system.textView, "frame.notification"),
        ] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: object, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(event) }
            })
        }
    }

    func begin(_ phase: String) {
        self.phase = phase
        minimumY = scroll.contentView.bounds.minY
        observations = 0
    }

    func record(_ event: String) {
        let clip = scroll.contentView.bounds
        let frame = system.textView.frame
        minimumY = min(minimumY, clip.minY)
        observations += 1
        guard observations <= 80 else { return }
        let value: [String: Any] = [
            "mode": mode, "phase": phase, "event": event,
            "uptime": ProcessInfo.processInfo.systemUptime,
            "clipY": clip.minY, "clipHeight": clip.height, "documentHeight": frame.height,
            "documentWidth": frame.width, "selection": system.selectedRange.location,
            "containerWidth": system.textView.textContainer?.size.width ?? -1,
            "viewFont": system.textView.font?.fontName ?? "nil",
            "viewFontSize": system.textView.font?.pointSize ?? -1,
            "typingFont": (system.textView.typingAttributes[.font] as? NSFont)?.fontName ?? "nil",
            "typingFontSize": (system.textView.typingAttributes[.font] as? NSFont)?.pointSize ?? -1,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("APPEARANCE_GEOMETRY " + line)
        }
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
