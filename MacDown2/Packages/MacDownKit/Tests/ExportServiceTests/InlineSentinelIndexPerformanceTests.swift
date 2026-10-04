@testable import ExportService
import Foundation
import Testing

/// `match(startingAt:)` tested the prefix of every spec for every hit: 4000 inline contributions took 3.5 s.
struct InlineSentinelIndexPerformanceTests {
    @Test func manyInlineSentinelsAreMatchedByLookupNotByScanningEverySpec() {
        let count = 20000
        let specs = (0 ..< count).map {
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE\($0)Z", isBlock: false, html: "<i>\($0)</i>")
        }
        let index = InlineSentinelIndex(specs)
        let text = (0 ..< count).map { "E12INLINE\($0)Z" }.joined(separator: " ")
        let start = ContinuousClock.now

        var found = 0
        var cursor = text.startIndex
        while let match = index.firstMatch(in: text, from: cursor) {
            found += 1
            cursor = match.range.upperBound
        }

        #expect(found == count)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func aSentinelThatIsOnlyAPrefixOfAnotherIsNotMistakenForIt() {
        let specs = [
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE1Z", isBlock: false, html: "one"),
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE10Z", isBlock: false, html: "ten"),
        ]
        let index = InlineSentinelIndex(specs)
        let text = "a E12INLINE10Z b E12INLINE1Z"

        let first = index.firstMatch(in: text, from: text.startIndex)
        #expect(first?.spec.html == "ten")
        let second = index.firstMatch(in: text, from: first?.range.upperBound ?? text.startIndex)
        #expect(second?.spec.html == "one")
    }

    /// Review pass 6: a sentinel's final `Z` followed by a grapheme-extending scalar (ZWNJ after Latin text in
    /// Persian, VS16, a combining mark) is one `Character`, so Character-level search and prefix tests missed it.
    @Test(arguments: ["\u{200C}", "\u{200D}", "\u{FE0F}", "\u{0301}"])
    func aSentinelFollowedByAnExtendingScalarIsFoundWithoutConsumingTheScalar(_ extender: String) {
        let spec = CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE3Z", isBlock: false, html: "<i/>")
        let index = InlineSentinelIndex([
            spec,
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE4Z", isBlock: false, html: ""),
        ])
        let text = "a E12INLINE3Z\(extender)ها"

        let found = index.firstMatch(in: text, from: text.startIndex)

        #expect(found?.spec.html == "<i/>")
        let consumed = found.map { String(text.unicodeScalars[$0.range]) }
        #expect(consumed == "E12INLINE3Z")
        let rest = found.map { String(text.unicodeScalars[$0.range.upperBound...]) }
        #expect(rest == "\(extender)ها")
    }
}
