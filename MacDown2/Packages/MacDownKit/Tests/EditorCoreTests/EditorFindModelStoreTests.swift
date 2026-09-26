@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.14, Slice 5a — per-identity caching for `EditorFindModel`,
/// mirroring `EditorTextSystemTests`' own store coverage for
/// `EditorTextSystemStore`.
@MainActor
@Suite("EditorFindModelStore (Slice 5a)")
struct EditorFindModelStoreTests {
    @Test("store caches and reuses models by identity")
    func storeReusesByIdentity() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString

        let first = store.model(for: identity)
        first.query = "needle"
        let second = store.model(for: identity)

        #expect(first === second)
        #expect(second.query == "needle")
    }

    @Test("a fresh model for a never-seen identity starts empty and inactive")
    func freshModelStartsEmptyAndInactive() {
        let store = EditorFindModelStore()
        let model = store.model(for: UUID().uuidString)

        #expect(model.query.isEmpty)
        #expect(model.isActive == false)
        #expect(model.matchCount == 0)
    }

    @Test("existingModel returns nil until a model has been created for that identity")
    func existingModelReturnsNilBeforeCreation() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString

        #expect(store.existingModel(for: identity) == nil)
        _ = store.model(for: identity)
        #expect(store.existingModel(for: identity) != nil)
    }

    @Test("evict removes the cached model for that identity")
    func evictRemovesModel() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString
        _ = store.model(for: identity)

        store.evict(identity)

        #expect(store.existingModel(for: identity) == nil)
        #expect(store.liveIdentities.isEmpty)
    }

    @Test("evictAll clears every cached model")
    func evictAllClearsEveryModel() {
        let store = EditorFindModelStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        _ = store.model(for: idA)
        _ = store.model(for: idB)

        store.evictAll()

        #expect(store.liveIdentities.isEmpty)
    }

    @Test("store tracks live identities")
    func liveIdentities() {
        let store = EditorFindModelStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString

        _ = store.model(for: idA)
        _ = store.model(for: idB)

        #expect(store.liveIdentities == Set([idA, idB]))
    }

    @Test("a model's state, including isActive, survives an evict-less re-fetch")
    func stateSurvivesReFetch() async {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString
        let model = store.model(for: identity)
        model.query = "cat"
        model.isActive = true
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        let reFetched = store.model(for: identity)

        #expect(reFetched.isActive)
        #expect(reFetched.matchCount == 2)
    }
}
