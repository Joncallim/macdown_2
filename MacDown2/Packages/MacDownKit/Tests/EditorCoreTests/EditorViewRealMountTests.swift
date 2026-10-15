import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// EPIC-22 Slice 2a — exercises `EditorView.makeNSView`/`dismantleNSView`
/// through the REAL SwiftUI `NSViewRepresentable` path (via
/// `NSHostingView`), not the lighter
/// `EditingAssistIntegrationSupport.makeSystem`/`makeCoordinator` helper
/// every other suite in this file uses.
///
/// This distinction is not academic: an earlier version of the
/// undo/redo-triggered gutter redraw registered its `NotificationCenter`
/// observer against `system.undoManager` evaluated inside `makeNSView`,
/// before the view had a window -- at which point it resolves to a
/// throwaway fallback manager, never the real one the window later
/// installs. Every OTHER test in this package mounts a bare
/// `EditorTextSystem`/`Coordinator` directly and never calls `makeNSView`
/// at all, so none of them could have caught that this specific
/// registration never actually fires in production. This suite exists
/// specifically to close that gap.
@MainActor
@Suite("EditorView real makeNSView path", .serialized)
struct EditorViewRealMountTests {
    private typealias Support = EditorViewRealMountSupport
    private typealias Mounted = Support.Mounted

    @Test func attachmentCallbackRunsAfterSameSizeWindowAttachment() async throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let signals = AsyncStream<Void>.makeStream()
        let mounted = Support.mount(
            initialText: "text",
            store: store,
            identity: identity,
            onLayoutChange: {
                guard let system = store.existingSystem(for: identity),
                      system.textView.window != nil,
                      !system.textView.bounds.isEmpty
                else { return }
                signals.continuation.yield(())
            }
        )
        defer { Support.close(mounted) }
        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView))
        #expect(scrollView.window === mounted.window)
        #expect(scrollView.bounds.size == CGSize(width: 400, height: 300))
        #expect(await Support.waitForSignal(signals.stream))
    }

    @Test func zeroSizeAttachmentCanReportUsableLayoutAfterWindowResize() async throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let signals = AsyncStream<Void>.makeStream()
        let resizedSignals = AsyncStream<Void>.makeStream()
        var waitingForResize = false
        let mounted = Support.mount(
            initialText: "text",
            store: store,
            identity: identity,
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            onLayoutChange: {
                guard let system = store.existingSystem(for: identity),
                      system.textView.window != nil,
                      !system.textView.bounds.isEmpty
                else { return }
                if waitingForResize {
                    resizedSignals.continuation.yield(())
                } else {
                    signals.continuation.yield(())
                }
            }
        )
        defer { Support.close(mounted) }
        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView))
        #expect(await Support.waitForSignal(signals.stream))
        mounted.hostingView.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        mounted.hostingView.layoutSubtreeIfNeeded()
        #expect(mounted.hostingView.bounds.isEmpty)

        waitingForResize = true
        mounted.window.setContentSize(NSSize(width: 400, height: 300))
        mounted.hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        mounted.hostingView.layoutSubtreeIfNeeded()
        #expect(await Support.waitForSignal(resizedSignals.stream))
        #expect(scrollView.window === mounted.window)
        #expect(scrollView.bounds.width > 0)
        #expect(scrollView.bounds.height > 0)
    }

    /// `makeNSView` pre-sized the text view with one `boundingRect` over the whole document, which is quadratic for
    /// CJK/emoji text: an 80 KB document froze the main thread for seconds when its tab opened.
    @Test func openingALargeCJKDocumentDoesNotFreezeTheMainThread() {
        let paragraph = String(repeating: "日本語のテキスト🙂", count: 40)
        let text = (0 ..< 80).map { _ in paragraph }.joined(separator: "\n")
        let start = ContinuousClock.now

        let mounted = Support.mount(initialText: text)
        defer { mounted.window.orderOut(nil) }

        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func fullLifecycleThroughRealSwiftUIMountingEditUndoRedoAndDismantle() throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        // Captured BEFORE mounting. The undo manager is the tab's own and keeps
        // its identity through mounting (it used to switch to the WINDOW's
        // manager, which every tab of a window shares).
        let systemBeforeMount = store.system(for: identity, initialText: "a", configuration: .default)
        let preMountUndoManagerIdentity = ObjectIdentifier(systemBeforeMount.undoManager)

        let mounted = Support.mount(initialText: "a", store: store, identity: identity)
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)

        let system = store.system(for: identity, initialText: "a", configuration: .default)
        #expect(
            preMountUndoManagerIdentity == ObjectIdentifier(system.undoManager),
            "the tab's undo manager must keep its identity once mounted in a real window"
        )
        #expect(system.textView.undoManager === system.undoManager)

        assertUndoRedoDrivesGutter(system: system, gutter: gutter)
        try assertDismantleLeavesNoObserver(mounted: mounted, scrollView: scrollView, system: system)
    }

    /// Edit past a digit boundary, then undo/redo, asserting the gutter
    /// tracks each direction without any extra prompting.
    private func assertUndoRedoDrivesGutter(system: EditorTextSystem, gutter: EditorGutterView) {
        let grownText = (1 ... 200).map { "line \($0)" }.joined(separator: "\n")
        system.textView.insertText(
            grownText,
            replacementRange: NSRange(location: 0, length: (system.text as NSString).length)
        )
        gutter.updateThickness()
        let thicknessAfterGrowing = gutter.ruleThickness

        system.undoManager.undo()
        #expect(
            gutter.ruleThickness < thicknessAfterGrowing,
            "gutter did not shrink after undo through the real makeNSView-mounted path"
        )

        // Redo must grow it back too -- proving the fix isn't
        // one-directional (e.g. an observer that only happens to fire once).
        system.undoManager.redo()
        #expect(
            gutter.ruleThickness == thicknessAfterGrowing,
            "gutter did not grow back after redo through the real makeNSView-mounted path"
        )
    }

    /// Calls the REAL `EditorView.dismantleNSView(_:coordinator:)`
    /// directly, rather than trying to force SwiftUI's own view-identity
    /// switch to trigger it: empirically, in this headless test process
    /// (no live `NSApplication` run loop driving an actual display-link
    /// update cycle), switching a hosted branch and pumping the run loop
    /// does NOT reliably make `NSHostingView` tear down the outgoing
    /// `NSViewRepresentable` at all -- confirmed by a first version of this
    /// test, which found `coordinator.gutterView` still non-nil afterward.
    /// `dismantleNSView`'s body never reads `self` (only its two
    /// parameters), so calling it on a throwaway `EditorView` value with
    /// the REAL `scrollView`/`coordinator` is not a workaround; it
    /// exercises the exact same production code SwiftUI would call.
    ///
    /// A first version of the leak assertion itself only checked the
    /// ALREADY-mounted `gutter`'s `ruleThickness` afterward, which an
    /// independent hostile review correctly flagged as unable to
    /// distinguish "the observer was removed" from "the observer is still
    /// registered but harmlessly no-ops", since `dismantleNSView`
    /// unconditionally sets `coordinator.gutterView = nil` REGARDLESS of
    /// whether `removeObserver` also ran -- `Coordinator.undoManagerDidChange`'s
    /// entire body is `gutterView?.updateThickness()`, so that version
    /// would have passed even with `removeObserver` deleted entirely. This
    /// version reassigns a FRESH `gutterView` onto the same coordinator
    /// after dismantle, restoring a non-nil target so a still-registered
    /// observer would have something to visibly act on.
    private func assertDismantleLeavesNoObserver(
        mounted _: Mounted,
        scrollView: NSScrollView,
        system: EditorTextSystem
    ) throws {
        let coordinator = try #require(
            system.textView.delegate as? EditorView.Coordinator,
            "expected the real Coordinator to still be the text view's delegate before dismantle"
        )

        Support.dismantleThroughTheProtocol(EditorView.self, scrollView, coordinator)

        #expect(coordinator.gutterView == nil, "dismantleNSView did not clear the coordinator's gutterView")

        // Grow the document (directly against `system`, bypassing the now
        // fully detached view) so a real `updateThickness()` call WOULD
        // produce a different thickness than this scratch gutter's own
        // freshly-computed one, giving a leaked observer something to
        // visibly change.
        let scratchScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let scratchGutter = EditorGutterView(scrollView: scratchScrollView, system: system)
        coordinator.gutterView = scratchGutter
        system.textView.insertText(
            (1 ... 500).map { "line \($0)" }.joined(separator: "\n"),
            replacementRange: NSRange(location: 0, length: (system.text as NSString).length)
        )
        let thicknessBeforeSyntheticNotifications = scratchGutter.ruleThickness

        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: system.undoManager)
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: system.undoManager)

        #expect(
            scratchGutter.ruleThickness == thicknessBeforeSyntheticNotifications,
            """
            a synthetic undo/redo notification still reached the coordinator after dismantle -- the \
            NotificationCenter observer was not actually removed, only masked by gutterView being nil
            """
        )
    }

    @Test func gutterResizesAfterAModelTextPushAcrossADigitBoundaryGrowing() throws {
        let mounted = Support.mount(initialText: "a")
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)
        let thicknessBefore = gutter.ruleThickness
        let lineCountBefore = mounted.store.system(
            for: mounted.identity,
            initialText: "",
            configuration: .default
        ).lineIndex.lineCount

        // 9 -> 100 lines, through the BINDING (a model-driven change, e.g.
        // a document reload), not through `textView.insertText` -- this
        // goes through `updateNSView`'s `system.setText(text)` path, which
        // bypasses the incremental delegate hooks entirely.
        Support.pushModelText((1 ... 100).map { "line \($0)" }.joined(separator: "\n"), into: mounted)

        let system = mounted.store.system(for: mounted.identity, initialText: "", configuration: .default)
        #expect(system.lineIndex.lineCount == 100)
        #expect(system.lineIndex.lineCount > lineCountBefore)
        #expect(
            gutter.ruleThickness > thicknessBefore,
            "gutter did not resize after a growing model text push crossing a digit boundary"
        )
    }

    @Test func gutterResizesAfterAModelTextPushAcrossADigitBoundaryShrinking() throws {
        let mounted = Support.mount(initialText: (1 ... 100).map { "line \($0)" }.joined(separator: "\n"))
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)
        gutter.updateThickness()
        let thicknessBefore = gutter.ruleThickness

        // 100 -> 9 lines, the mirror direction: shrinking must update the
        // ruler immediately too, not just growing.
        Support.pushModelText((1 ... 9).map { "line \($0)" }.joined(separator: "\n"), into: mounted)

        let system = mounted.store.system(for: mounted.identity, initialText: "", configuration: .default)
        #expect(system.lineIndex.lineCount == 9)
        #expect(
            gutter.ruleThickness < thicknessBefore,
            "gutter did not shrink after a shrinking model text push crossing a digit boundary"
        )
    }

    @Test func gutterExposesBasicAccessibilityMetadataWithoutPerLineChildren() throws {
        let mounted = Support.mount(initialText: (1 ... 50).map { "line \($0)" }.joined(separator: "\n"))
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Support.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)

        #expect(gutter.isAccessibilityElement())
        #expect(gutter.accessibilityIdentifier() == "editorGutter")
        #expect(!(gutter.accessibilityLabel() ?? "").isEmpty)
        // A single accessibility element for the whole ruler -- VoiceOver
        // must not be asked to traverse one child per visible line.
        #expect((gutter.accessibilityChildren() ?? []).isEmpty)
    }

    @Test func anOlderMountsTeardownDoesNotDetachANewerMount() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "text")
        let older = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        let olderScroll = NSScrollView(frame: .zero)
        system.scrollView = olderScroll

        let newer = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        let newerScroll = NSScrollView(frame: .zero)
        system.scrollView = newerScroll
        system.textView.delegate = newer

        Support.dismantleThroughTheProtocol(EditorView.self, olderScroll, older)

        #expect(system.textView.delegate === newer)
        #expect(system.scrollView === newerScroll)
    }

    @Test func theCurrentMountsTeardownDetachesTheSharedTextViewAndScrollView() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "text")
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        let scroll = NSScrollView(frame: .zero)
        system.scrollView = scroll

        Support.dismantleThroughTheProtocol(EditorView.self, scroll, coordinator)

        #expect(system.textView.delegate == nil)
        #expect(system.scrollView == nil)
    }
}
