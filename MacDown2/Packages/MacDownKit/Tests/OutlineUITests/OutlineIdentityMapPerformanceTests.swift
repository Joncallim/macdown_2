import Foundation
@testable import MarkdownEngine
@testable import OutlineUI
import Testing

/// `remap` filtered every candidate heading for every collapsed id (2000 ids over 100k identical headings: ~40 s).
struct OutlineIdentityMapPerformanceTests {
    private func headings(_ titles: [String]) -> [HeadingItem] {
        titles.enumerated().map { HeadingItem(level: 2, title: $1, lineRange: ($0 + 1) ... ($0 + 1)) }
    }

    /// The previous algorithm, kept as the oracle: nearest unclaimed candidate, lower ordinal wins ties.
    private func reference(_ ids: Set<Int>, from old: [HeadingItem], to new: [HeadingItem]) -> Set<Int> {
        var byKey: [String: [Int]] = [:]
        for (ordinal, heading) in new
            .enumerated() {
            byKey["\(heading.level)|\(heading.title)", default: []].append(ordinal)
        }
        var claimed: Set<Int> = []
        var result: Set<Int> = []
        for oldID in ids.sorted() where old.indices.contains(oldID) {
            let key = "\(old[oldID].level)|\(old[oldID].title)"
            let available = (byKey[key] ?? []).filter { !claimed.contains($0) }
            guard let nearest = available.min(by: { abs($0 - oldID) < abs($1 - oldID) }) else { continue }
            claimed.insert(nearest)
            result.insert(nearest)
        }
        return result
    }

    @Test func theFastPathAgreesWithTheReferenceOnRandomDocuments() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 300 {
            let titles = ["A", "B", "C"]
            let old = headings((0 ..< Int.random(in: 1 ... 40, using: &generator)).map { _ in
                titles.randomElement(using: &generator) ?? "A"
            })
            let new = headings((0 ..< Int.random(in: 1 ... 40, using: &generator)).map { _ in
                titles.randomElement(using: &generator) ?? "A"
            })
            let ids = Set((0 ..< old.count).filter { _ in Bool.random(using: &generator) })

            #expect(OutlineIdentityMap.remap(ids, from: old, to: new) == reference(ids, from: old, to: new))
        }
    }

    @Test func manyCollapsedItemsOverManyIdenticalHeadingsRemapQuickly() {
        let all = headings(Array(repeating: "Same", count: 100_000))
        let collapsed = Set(stride(from: 0, to: 100_000, by: 50))
        let start = ContinuousClock.now

        let remapped = OutlineIdentityMap.remap(collapsed, from: all, to: all)

        #expect(remapped == collapsed)
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
