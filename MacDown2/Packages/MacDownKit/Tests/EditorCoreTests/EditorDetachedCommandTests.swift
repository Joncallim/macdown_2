import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

private final class DetachedModel: ObservableObject {
    @Published var text = "b\na\n"
    @Published var showsEditor = true
}

private struct DetachedHost: View {
    @ObservedObject var model: DetachedModel
    let store: EditorTextSystemStore
    let identity: String

    var body: some View {
        VStack {
            if model.showsEditor {
                EditorView(
                    text: Binding(get: { model.text }, set: { model.text = $0 }),
                    identity: identity, configuration: .default, store: store
                )
            }
            Text(model.text)
        }
    }
}

/// Round-6 review (6e146d89) P2: with the editor pane unmounted (Preview Only) the text view has no delegate, so a
/// command edit (Text Filter, snippet) reached the hidden view but never the model, and the next mount pushed the
/// model back, silently discarding the result. Commands must not run while the system is detached.
@MainActor
struct EditorDetachedCommandTests {
    private func spin() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    @Test func commandsAreRefusedWhileTheEditorPaneIsUnmountedAndAllowedAgainOnRemount() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = DetachedModel()
        let hosting = NSHostingView(rootView: DetachedHost(model: model, store: store, identity: identity))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        spin()
        let system = store.system(for: identity, initialText: model.text, configuration: .default)
        #expect(system.canApplyCommandEdit, "mounted: commands are allowed")

        model.showsEditor = false // Preview Only
        spin()
        #expect(system.isDetachedFromEditorView)
        #expect(!system.canApplyCommandEdit, "unmounted: a command edit would never reach the model")

        model.showsEditor = true
        spin()
        #expect(!system.isDetachedFromEditorView)
        #expect(system.canApplyCommandEdit, "remounted: commands are allowed again")
    }
}
