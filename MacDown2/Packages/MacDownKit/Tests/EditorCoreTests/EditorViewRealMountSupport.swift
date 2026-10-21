import AppKit
@testable import EditorCore
import Foundation
import SwiftUI

/// Mounting helpers for `EditorViewRealMountTests`: hosts a real
/// `EditorView` in an `NSHostingView`/`NSWindow` so `makeNSView`,
/// `updateNSView` and `dismantleNSView` run through SwiftUI itself.
@MainActor
enum EditorViewRealMountSupport {
    struct Mounted {
        let hostingView: NSHostingView<EditorView>
        let window: NSWindow
        let store: EditorTextSystemStore
        let identity: String
    }

    static func mount(
        initialText: String,
        store: EditorTextSystemStore = EditorTextSystemStore(),
        identity: String = UUID().uuidString,
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300),
        onLayoutChange: (() -> Void)? = nil
    ) -> Mounted {
        let binding = Binding<String>(get: { initialText }, set: { _ in })

        let hostingView = NSHostingView(rootView: EditorView(
            text: binding,
            identity: identity,
            configuration: .default,
            store: store,
            onLayoutChange: onLayoutChange
        ))
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // The test retains the window through teardown; keep AppKit from
        // releasing it again when close() removes it from the window list.
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        return Mounted(hostingView: hostingView, window: window, store: store, identity: identity)
    }

    static func waitForSignal(_ stream: AsyncStream<Void>, timeout: Duration = .seconds(2)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    static func close(_ mounted: Mounted) {
        mounted.window.contentView = nil
        mounted.window.close()
    }

    static func pushModelText(_ newText: String, into mounted: Mounted) {
        let binding = Binding<String>(get: { newText }, set: { _ in })
        mounted.hostingView.rootView = EditorView(
            text: binding,
            identity: mounted.identity,
            configuration: .default,
            store: mounted.store
        )
        mounted.hostingView.layoutSubtreeIfNeeded()
    }

    static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// SwiftUI reaches teardown through the `NSViewRepresentable` requirement
    /// (`static func dismantleNSView`). Dispatching through the generic
    /// constraint is what proves the implementation is the protocol witness; an
    /// instance method of the same name is never called this way (#183 F09).
    static func dismantleThroughTheProtocol<V: NSViewRepresentable>(
        _: V.Type,
        _ view: V.NSViewType,
        _ coordinator: V.Coordinator
    ) {
        V.dismantleNSView(view, coordinator: coordinator)
    }
}
