import AppKit
import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

/// DIAG SCRATCH ONLY (pkg/diag, instrumented Neon + SwiftTreeSitter B1+B2).
/// For each failing NeonReplacementEditStrictTests case: trace Neon's calls, compare rendered
/// attributes per UTF-16 unit, compare Neon's edited LanguageLayer with a fresh one, and replay the
/// recorded root-layer call sequence on a new LanguageLayer (exact, points corrected, whole-doc resolve).
@MainActor
@Suite(.serialized)
struct NeonDivergenceDiagTests {
    static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024)
    static let registry = GrammarRegistry()

    enum Case: String { case typeThenDelete, replace600, replacePlain, widened }

    @Test func typeThenDelete() async throws { try await run(.typeThenDelete) }
    @Test func replace600() async throws { try await run(.replace600) }
    @Test func replacePlain() async throws { try await run(.replacePlain) }
    @Test func widened() async throws { try await run(.widened) }

    private func perform(_ c: Case, _ editor: HighlightedEditor) {
        let text = Self.text as NSString
        let middle = text.length / 2
        func typeRapidly() {
            for index in 0 ..< 11 { editor.typeOrDelete(at: middle, insert: index.isMultiple(of: 2)) }
        }
        switch c {
        case .typeThenDelete:
            typeRapidly()
            editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 1500))
        case .replace600:
            let range = NSRange(location: middle, length: 600)
            editor.textView.insertText(text.substring(with: range) + "y", replacementRange: range)
        case .replacePlain:
            let range = NSRange(location: middle, length: 600)
            let plain = String(text.substring(with: range).map { "*_`[]()".contains($0) ? " " : $0 })
            editor.textView.insertText(plain, replacementRange: range)
        case .widened:
            typeRapidly()
        }
    }

    // MARK: helpers

    static func byteColumnTransformer(_ s: String) -> Point.LocationTransformer {
        var starts = [0]
        for (i, c) in s.utf16.enumerated() where c == 10 { starts.append(i + 1) }
        return { loc in
            var lo = 0, hi = starts.count - 1
            while lo < hi { let m = (lo + hi + 1) / 2; if starts[m] <= loc { lo = m } else { hi = m - 1 } }
            return Point(row: lo, column: (loc - starts[lo]) * 2)
        }
    }

    static func newLayer() throws -> LanguageLayer {
        let config = try #require(registry.configuration(for: "markdown"))
        return try LanguageLayer(languageConfig: config, configuration: .init(languageProvider: registry.languageProvider))
    }

    static func freshLayer(_ text: String) throws -> LanguageLayer {
        let layer = try newLayer()
        layer.replaceContent(with: text, transformer: byteColumnTransformer(text))
        return layer
    }

    static func highlightSet(_ layer: LanguageLayer, _ text: String) throws -> Set<String> {
        let n = text.utf16.count
        let hl = try layer.highlights(in: NSRange(location: 0, length: n), provider: text.predicateTextProvider)
        return Set(hl.map { "\($0.name)@\($0.range.location)+\($0.range.length)" })
    }

    static func inlineRanges(_ layer: LanguageLayer) -> Set<String> {
        Set((layer.diagTree("markdown_inline")?.includedRanges ?? []).filter { !$0.bytes.isEmpty }
            .map { "\($0.bytes.lowerBound / 2)..<\($0.bytes.upperBound / 2)" })
    }

    /// Nodes whose start point disagrees with the byte-column point of their start byte.
    static func badPoints(_ tree: MutableTree?, _ text: String) -> (nodes: Int, bad: Int, first: String) {
        guard let root = tree?.rootNode else { return (0, 0, "") }
        let t = byteColumnTransformer(text)
        var nodes = 0, bad = 0, first = ""
        var stack = [root]
        while let node = stack.popLast() {
            nodes += 1
            let loc = Int(node.byteRange.lowerBound) / 2
            if let p = t(loc), p != node.pointRange.lowerBound {
                bad += 1
                if first.isEmpty { first = "\(node.nodeType ?? "?")@\(loc) tree=\(node.pointRange.lowerBound) correct=\(p)" }
            }
            for i in 0 ..< node.childCount { if let ch = node.child(at: i) { stack.append(ch) } }
        }
        return (nodes, bad, first)
    }

    static func compareLayers(_ label: String, _ a: LanguageLayer, _ b: LanguageLayer, _ text: String, spans: [NSRange]) throws {
        let ha = try highlightSet(a, text), hb = try highlightSet(b, text)
        let onlyA = ha.subtracting(hb), onlyB = hb.subtracting(ha)
        let mdEq = a.diagTree(a.languageName)?.rootNode?.sExpressionString == b.diagTree(a.languageName)?.rootNode?.sExpressionString
        let inEq = a.diagTree("markdown_inline")?.rootNode?.sExpressionString == b.diagTree("markdown_inline")?.rootNode?.sExpressionString
        let ra = inlineRanges(a), rb = inlineRanges(b)
        func inSpan(_ s: String) -> Bool {
            let parts = s.split(separator: "@").last!.split(separator: "+")
            let loc = Int(parts[0])!, len = Int(parts[1])!
            return spans.contains { NSIntersectionRange($0, NSRange(location: loc, length: max(len, 1))).length > 0 }
        }
        print("DIAG-LAYER \(label): mdSexpEqual=\(mdEq) inlineSexpEqual=\(inEq) inlineRanges a=\(ra.count) b=\(rb.count) onlyA=\(ra.subtracting(rb).sorted().prefix(6)) onlyB=\(rb.subtracting(ra).sorted().prefix(6)) highlights a=\(ha.count) b=\(hb.count) onlyA=\(onlyA.count) onlyB=\(onlyB.count) onlyAInRenderedSpans=\(onlyA.filter(inSpan).count) onlyBInRenderedSpans=\(onlyB.filter(inSpan).count)")
        print("DIAG-LAYER \(label): onlyA sample=\(onlyA.sorted().prefix(6)) onlyB sample=\(onlyB.sorted().prefix(6))")
        let pa = badPoints(a.diagTree(a.languageName), text), pb = badPoints(b.diagTree(a.languageName), text)
        print("DIAG-POINTS \(label): markdown nodes a=\(pa.nodes) badPoints a=\(pa.bad) [\(pa.first)] b=\(pb.nodes) badPoints b=\(pb.bad) [\(pb.first)]")
    }

    /// Per-unit diff of rendered signatures, grouped into spans.
    static func spans(_ edited: [RenderedRun], _ fresh: [RenderedRun], text: String) -> [(NSRange, String, String)] {
        let length = (text as NSString).length
        func map(_ runs: [RenderedRun]) -> [String] {
            var sig = [String](repeating: "-", count: length)
            for run in runs {
                let upper = min(NSMaxRange(run.range), length)
                guard run.range.location < upper else { continue }
                for i in run.range.location ..< upper { sig[i] = run.signature }
            }
            return sig
        }
        let a = map(edited), b = map(fresh)
        var out: [(NSRange, String, String)] = []
        var i = 0
        while i < length {
            if a[i] == b[i] { i += 1; continue }
            var j = i
            while j < length, a[j] != b[j], a[j] == a[i], b[j] == b[i] { j += 1 }
            out.append((NSRange(location: i, length: j - i), a[i], b[i]))
            i = j
        }
        return out
    }

    static func printSpans(_ label: String, _ spans: [(NSRange, String, String)], text: String) {
        let ns = text as NSString
        print("DIAG-RENDER \(label): spans=\(spans.count) units=\(spans.reduce(0) { $0 + $1.0.length })")
        for (range, a, b) in spans.prefix(40) {
            let lo = max(0, range.location - 15), hi = min(ns.length, NSMaxRange(range) + 15)
            let ctx = ns.substring(with: NSRange(location: lo, length: hi - lo)).replacingOccurrences(of: "\n", with: "\\n")
            let inner = ns.substring(with: range).replacingOccurrences(of: "\n", with: "\\n")
            print("DIAG-SPAN \(label) \(range.location)..<\(NSMaxRange(range)) edited=\(a) fresh=\(b) text='\(inner)' ctx='\(ctx)'")
        }
    }

    /// Replays the recorded root-layer calls on a new layer.
    static func replay(_ events: [DiagEvent], correctPoints: Bool, wholeDocResolveAtEnd: Bool) throws -> (LanguageLayer, Int) {
        let layer = try newLayer()
        var prevText = ""
        var inconsistent = 0
        for event in events {
            switch event {
            case let .edit(e, text):
                var edit = e
                if correctPoints {
                    let start = Int(e.startByte) / 2, oldEnd = Int(e.oldEndByte) / 2, newEnd = Int(e.newEndByte) / 2
                    let tn = byteColumnTransformer(text), to = byteColumnTransformer(prevText)
                    let p = prevText as NSString, n = text as NSString
                    // consistency: prefix before start and text after oldEnd/newEnd must match (within both reads)
                    let pre = min(start, p.length, n.length)
                    let sufOld = max(0, p.length - oldEnd), sufNew = max(0, n.length - newEnd)
                    if p.substring(to: pre) != n.substring(to: pre) || (oldEnd <= p.length && newEnd <= n.length &&
                        p.substring(from: oldEnd).prefix(min(sufOld, sufNew)) != n.substring(from: newEnd).prefix(min(sufOld, sufNew))) {
                        inconsistent += 1
                    }
                    edit = InputEdit(startByte: e.startByte, oldEndByte: e.oldEndByte, newEndByte: e.newEndByte,
                                     startPoint: tn(start)!, oldEndPoint: to(min(oldEnd, p.length))!, newEndPoint: tn(newEnd)!)
                }
                _ = layer.didChangeContent(LanguageLayer.Content(string: text), using: edit, resolveSublayers: false)
                prevText = text
            case let .resolve(set, text):
                _ = try layer.resolveSublayers(with: LanguageLayer.Content(string: text), in: set)
            }
        }
        if wholeDocResolveAtEnd {
            _ = try layer.resolveSublayers(with: LanguageLayer.Content(string: prevText), in: IndexSet(integersIn: 0 ..< prevText.utf16.count))
        }
        return (layer, inconsistent)
    }

    // MARK: run

    private func run(_ c: Case) async throws {
        let label = c.rawValue
        DiagTrace.tag = label
        DiagTrace.events = []
        DiagTrace.recording = true
        DiagTrace.enabled = false
        let rootsBefore = DiagTrace.rootLayers.count
        let editor = HighlightedEditor(text: Self.text, widensEdits: c == .widened)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        let neonLayer = DiagTrace.rootLayers[rootsBefore]
        let openEvents = DiagTrace.events.count
        DiagTrace.log("=== open done: \(openEvents) root events; visible=\(editor.textView.visibleRect) frame=\(editor.textView.frame) length=\(editor.textView.string.utf16.count)")
        DiagTrace.enabled = true
        perform(c, editor)
        DiagTrace.log("=== edit calls returned")
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(3)))
        DiagTrace.log("=== quiet")
        DiagTrace.enabled = false
        DiagTrace.recording = false
        let events = DiagTrace.events
        let text = editor.textView.string

        let rootsBeforeFresh = DiagTrace.rootLayers.count
        let fresh = HighlightedEditor(text: text)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .seconds(2)))
        let freshNeonLayer = DiagTrace.rootLayers[rootsBeforeFresh]
        let edited = editor.renderedRuns(), freshRuns = fresh.renderedRuns()
        let diff = Self.spans(edited, freshRuns, text: text)
        Self.printSpans(label, diff, text: text)
        let spanRanges = diff.map(\.0)

        print("DIAG-EVENTS \(label): open=\(openEvents) total=\(events.count)")
        for (i, e) in events.enumerated() where i >= openEvents {
            switch e {
            case let .edit(edit, t): print("DIAG-EVENT \(label) #\(i) edit \(DiagTrace.edit(edit)) textLen=\(t.utf16.count)")
            case let .resolve(set, t): print("DIAG-EVENT \(label) #\(i) resolve \(DiagTrace.ranges(set)) textLen=\(t.utf16.count)")
            }
        }

        let freshLayer = try Self.freshLayer(text)
        try Self.compareLayers("\(label) neonEdited-vs-freshLayer", neonLayer, freshLayer, text, spans: spanRanges)
        try Self.compareLayers("\(label) neonFresh-vs-freshLayer", freshNeonLayer, freshLayer, text, spans: spanRanges)

        for (correct, whole) in [(false, false), (true, false), (false, true), (true, true)] {
            let (r, inconsistent) = try Self.replay(events, correctPoints: correct, wholeDocResolveAtEnd: whole)
            let tag = "\(label) replay(correctPoints=\(correct),wholeDocResolve=\(whole))"
            print("DIAG-REPLAY \(tag) inconsistentEdits=\(inconsistent) sameHighlightsAsNeonEdited=\(try Self.highlightSet(r, text) == Self.highlightSet(neonLayer, text))")
            try Self.compareLayers("\(tag)-vs-freshLayer", r, freshLayer, text, spans: spanRanges)
        }

        // Styling vs tree: re-query everything from the existing parse state.
        editor.highlighter.invalidateAll()
        _ = await editor.waitUntilQuiet(quietPeriod: .seconds(3))
        let afterAll = editor.renderedRuns()
        let d2 = Self.spans(afterAll, freshRuns, text: text)
        print("DIAG-INVALIDATEALL \(label) equalToFresh=\(afterAll == freshRuns)")
        Self.printSpans("\(label)-afterInvalidateAll", d2, text: text)

        // Then resolve sublayers over the whole document on Neon's own layer and re-query.
        _ = try neonLayer.resolveSublayers(with: LanguageLayer.Content(string: text), in: IndexSet(integersIn: 0 ..< text.utf16.count))
        editor.highlighter.invalidateAll()
        _ = await editor.waitUntilQuiet(quietPeriod: .seconds(3))
        let afterResolve = editor.renderedRuns()
        print("DIAG-WHOLERESOLVE+INVALIDATEALL \(label) equalToFresh=\(afterResolve == freshRuns)")
        Self.printSpans("\(label)-afterWholeResolve", Self.spans(afterResolve, freshRuns, text: text), text: text)
        try Self.compareLayers("\(label) neonEdited(afterWholeResolve)-vs-freshLayer", neonLayer, freshLayer, text, spans: spanRanges)
    }
}
