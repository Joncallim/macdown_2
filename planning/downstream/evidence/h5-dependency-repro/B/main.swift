// Problem B repro: SwiftTreeSitterLayer only (no Neon). markdown root + markdown_inline sublayer.
import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import TSMarkdown
import TSMarkdownInline

let qdir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("queries")
let mdConfig = try LanguageConfiguration(tree_sitter_markdown(), name: "markdown",
                                         queriesURL: qdir.appendingPathComponent("markdown"))
let inlineConfig = try LanguageConfiguration(tree_sitter_markdown_inline(), name: "markdown_inline",
                                             queriesURL: qdir.appendingPathComponent("markdown_inline"))
let layerConfig = LanguageLayer.Configuration(languageProvider: { $0 == "markdown_inline" ? inlineConfig : nil })

// Same fixture block as MacDownKit StallFixtures (48 KB).
let block = """
# Heading with `code`

Some *emphasis*, **strong** text and a [link](https://example.com) here.

- list item one with `inline`
- list item two

> a quote with **bold**

```
fenced code line
```



"""
var base = ""
while base.utf8.count < 48 * 1024 { base += block }

func transformer(_ s: String) -> Point.LocationTransformer {
    var starts = [0]
    for (i, c) in s.utf16.enumerated() where c == 10 { starts.append(i + 1) }
    return { loc in
        var lo = 0, hi = starts.count - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if starts[m] <= loc { lo = m } else { hi = m - 1 } }
        return Point(row: lo, column: (loc - starts[lo]) * 2)
    }
}

func freshLayer(_ text: String) throws -> LanguageLayer {
    let layer = try LanguageLayer(languageConfig: mdConfig, configuration: layerConfig)
    _ = layer.replaceContent(with: text, transformer: transformer(text))
    return layer
}

func inlineTree(_ layer: LanguageLayer) -> Tree? {
    layer.snapshot()?.sublayerSnapshots.first(where: { $0.rootSnapshot.data.name == "markdown_inline" })?.rootSnapshot.tree
}

func fmt(_ r: TSRange) -> String { "[\(r.bytes.lowerBound / 2), \(r.bytes.upperBound / 2))" }

func analyse(_ ranges: [TSRange]) -> (zero: [TSRange], overlaps: [(TSRange, TSRange)]) {
    let zero = ranges.filter { $0.bytes.isEmpty }
    var overlaps = [(TSRange, TSRange)]()
    for i in 1 ..< max(1, ranges.count) where ranges[i].bytes.lowerBound < ranges[i - 1].bytes.upperBound {
        overlaps.append((ranges[i - 1], ranges[i]))
    }
    return (zero, overlaps)
}

func highlights(_ layer: LanguageLayer, _ text: String) throws -> Set<String> {
    let n = text.utf16.count
    let hl = try layer.highlights(in: NSRange(location: 0, length: n), provider: text.predicateTextProvider)
    return Set(hl.map { "\($0.name)@\($0.range.location)+\($0.range.length)" })
}

/// One edit expressed in pre-edit UTF-16 coordinates, Neon-style: didChangeContent(resolveSublayers:false)
struct Edit { let range: NSRange; let replacement: String }

func run(_ title: String, edits: [Edit], resolveWholeDoc: Bool) throws {
    print("\n=== \(title) (resolve in \(resolveWholeDoc ? "whole document" : "invalidated set")) ===")
    var text = base
    let layer = try freshLayer(text)
    let before = inlineTree(layer)!.includedRanges
    print("inline ranges before: \(before.count)")
    IncludedRangesDiagnostics.reset()
    var invalid = IndexSet()
    for e in edits {
        let oldEnd = transformer(text)(e.range.upperBound) ?? .zero
        let ns = text as NSString
        text = ns.replacingCharacters(in: e.range, with: e.replacement)
        let delta = e.replacement.utf16.count - e.range.length
        let edit = InputEdit(startByte: e.range.location * 2, oldEndByte: e.range.upperBound * 2,
                             newEndByte: (e.range.upperBound + delta) * 2,
                             startPoint: transformer(text)(e.range.location)!, oldEndPoint: oldEnd,
                             newEndPoint: transformer(text)(e.range.upperBound + delta)!)
        let set = layer.didChangeContent(LanguageLayer.Content(string: text), using: edit, resolveSublayers: false)
        invalid = invalid.applyingShift(delta, at: e.range.upperBound).union(set)
        print("edit \(e.range) -> \(e.replacement.utf16.count) units; after applyEdit+reparse inline ranges:")
        let mid = inlineTree(layer)!.includedRanges
        let a = analyse(mid)
        print("  count=\(mid.count) zero-length=\(a.zero.count) \(a.zero.prefix(6).map(fmt)) overlaps=\(a.overlaps.count)")
    }
    let n = text.utf16.count
    let resolveSet = resolveWholeDoc ? IndexSet(integersIn: 0 ..< n) : invalid
    _ = try layer.resolveSublayers(with: LanguageLayer.Content(string: text), in: resolveSet)
    let rejectedRanges = IncludedRangesDiagnostics.lastRejected
    print("ts_parser_set_included_ranges during edit+resolve: accepted=\(IncludedRangesDiagnostics.accepted) rejected=\(IncludedRangesDiagnostics.rejected)")
    if !rejectedRanges.isEmpty {
        let a = analyse(rejectedRanges)
        print("  rejected list: count=\(rejectedRanges.count) zero-length=\(a.zero.count) overlaps=\(a.overlaps.count)")
        for (p, q) in a.overlaps.prefix(4) { print("    overlap: \(fmt(p)) then \(fmt(q))") }
    }
    let after = inlineTree(layer)!.includedRanges
    let aa = analyse(after)
    print("inline ranges after resolve (tree): count=\(after.count) zero-length=\(aa.zero.count) overlaps=\(aa.overlaps.count)")

    let fresh = try freshLayer(text)
    let fr = inlineTree(fresh)!.includedRanges
    let afterSet = Set(after.filter { !$0.bytes.isEmpty }.map(fmt)), freshSet = Set(fr.map(fmt))
    print("fresh parse inline ranges: count=\(fr.count); non-empty ranges only in edited=\(afterSet.subtracting(freshSet).count) only in fresh=\(freshSet.subtracting(afterSet).count)")
    print("  only-in-fresh sample: \(freshSet.subtracting(afterSet).sorted().prefix(5))")
    print("  only-in-edited sample: \(afterSet.subtracting(freshSet).sorted().prefix(5))")
    let s1 = inlineTree(layer)!.rootNode?.sExpressionString ?? "", s2 = inlineTree(fresh)!.rootNode?.sExpressionString ?? ""
    print("inline tree sexp identical: \(s1 == s2) (len \(s1.count) vs \(s2.count))")
    let h1 = try highlights(layer, text), h2 = try highlights(fresh, text)
    print("highlight captures: edited=\(h1.count) fresh=\(h2.count) onlyEdited=\(h1.subtracting(h2).count) onlyFresh=\(h2.subtracting(h1).count)")
    print("  onlyFresh sample: \(h2.subtracting(h1).sorted().prefix(4))")
    print("VERDICT_ROW \(title) wholeDoc=\(resolveWholeDoc) rejected=\(IncludedRangesDiagnostics.rejected) zeroAfter=\(aa.zero.count) overlapsAfter=\(aa.overlaps.count) hlDiff=\(h1.symmetricDifference(h2).count)")
}

extension IndexSet {
    func applyingShift(_ delta: Int, at location: Int) -> IndexSet { var s = self; s.shift(startingAt: location, by: delta); return s }
}

let n = base.utf16.count
let mid = n / 2
let replRange = NSRange(location: mid, length: 600)
let replacement = (base as NSString).substring(with: replRange) + "y"

for whole in [false, true] {
    try run("A_control_typing", edits: [Edit(range: NSRange(location: mid, length: 0), replacement: "x")], resolveWholeDoc: whole)
    try run("B_replace600", edits: [Edit(range: replRange, replacement: replacement)], resolveWholeDoc: whole)
    try run("C_deleteBlock", edits: [Edit(range: NSRange(location: 1000, length: 1500), replacement: "")], resolveWholeDoc: whole)
    try run("D_type_then_delete_one_turn",
            edits: [Edit(range: NSRange(location: mid, length: 0), replacement: "x"),
                    Edit(range: NSRange(location: 1000, length: 1500), replacement: "")], resolveWholeDoc: whole)
}
