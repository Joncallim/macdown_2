import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("EditorTextSystem")
struct EditorTextSystemTests {
    private func makeSystem(text: String = "") -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
    }

    @Test("initial text is set")
    func initialText() {
        let system = makeSystem(text: "hello")
        #expect(system.text == "hello")
    }

    @Test("setText replaces content")
    func setTextReplaces() {
        let system = makeSystem(text: "hello")
        system.setText("world")
        #expect(system.text == "world")
    }

    @Test("selectedRange can be read and written")
    func selectedRangeRoundTrip() {
        let system = makeSystem(text: "hello world")
        system.selectedRange = NSRange(location: 2, length: 3)
        #expect(system.selectedRange == NSRange(location: 2, length: 3))
    }

    @Test("each text system has an independent undo manager")
    func undoIsPerSystem() {
        let systemA = makeSystem(text: "A")
        let systemB = makeSystem(text: "B")

        #expect(systemA.undoManager !== systemB.undoManager)
    }

    @Test("store caches and reuses systems by identity")
    func storeReusesByIdentity() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        let first = store.system(for: identity, initialText: "first", configuration: .default)
        let second = store.system(for: identity, initialText: "second", configuration: .default)

        #expect(first === second)
        #expect(first.text == "first")
    }

    @Test("evict removes the cached system")
    func evictRemovesSystem() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        weak var weakSystem: EditorTextSystem?
        autoreleasepool {
            let system = store.system(for: identity, initialText: "", configuration: .default)
            weakSystem = system
            store.evict(identity)
        }

        #expect(store.liveIdentities.isEmpty)
        #expect(weakSystem == nil)
    }

    @Test("store tracks live identities")
    func liveIdentities() {
        let store = EditorTextSystemStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString

        _ = store.system(for: idA, initialText: "", configuration: .default)
        _ = store.system(for: idB, initialText: "", configuration: .default)

        #expect(store.liveIdentities == Set([idA, idB]))
    }

    @Test("undo stack survives evict-less re-fetch from store")
    func undoSurvivesReFetch() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        let first = store.system(for: identity, initialText: "hello", configuration: .default)
        // Register a trivial undo action directly; AppKit's text view does not
        // register undos in a headless test environment.
        first.undoManager.registerUndo(withTarget: first) { _ in }
        #expect(first.undoManager.canUndo)

        let second = store.system(for: identity, initialText: "", configuration: .default)
        #expect(second === first)
        #expect(second.undoManager.canUndo)
    }
}
