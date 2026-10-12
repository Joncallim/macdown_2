import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

private final class NeverMountedModel: ObservableObject {
    @Published var text = "a\r\nb\r\n"
    @Published var showsEditor = false // window opened or restored in Preview Only
}

private struct NeverMountedHost: View {
    @ObservedObject var model: NeverMountedModel
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

/// Round-7 review (54b06b3a) P2: a system created ahead of any mount (the window's eager session set-up) in a
/// window that stays in Preview Only accepted command edits that could never reach the model.
@MainActor
struct EditorNeverMountedCommandTests {
    @Test func aSystemMarkedAwaitingItsViewRefusesCommandsUntilTheViewMounts() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = NeverMountedModel()
        let system = store.system(for: identity, initialText: model.text, configuration: .default)
        system.setAwaitingEditorView(true) // what WindowController.makeSessionsForActiveTab does
        let hosting = NSHostingView(rootView: NeverMountedHost(model: model, store: store, identity: identity))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        #expect(!system.canApplyCommandEdit, "never mounted: a command edit cannot reach the model")
        #expect(!system.convertLineEndings(to: .lineFeed), "the command must decline rather than edit the hidden view")

        model.showsEditor = true
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(system.canApplyCommandEdit, "mounted: commands are allowed")
    }
}
