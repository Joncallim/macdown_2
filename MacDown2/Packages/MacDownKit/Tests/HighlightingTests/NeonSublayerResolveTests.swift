import AppKit
import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterClient

/// DEP-TRIAL ONLY (stage C2, `planning/downstream/evidence/h5-neon-resolve/`).
///
/// Neon 484d6fb9 never resolves sublayers after an edit: `TreeSitterClient`
/// reports edit invalidations with `sublayers: false`, and the sublayer
/// validator's valid set (the whole document after open) survives an interior
/// edit, so the `markdown_inline` sublayer keeps its edited, stale ranges.
/// These tests require the final rendered attributes (or, for the client-level
/// scroll tests, the highlight captures) to equal a fresh highlighter's for
/// every UTF-16 unit, after:
///
/// - single interior replacements, deletions and insertions inside and across
///   block boundaries, including deleted markup with no replacement range;
/// - edits made while the sublayer valid set is split by scrolling (client level:
///   only the "visible" windows are queried, so only they are resolved);
/// - large (>= 2,048 units, background-parsed) edits, followed by more edits in
///   the same turn and in later turns while the parse may still be in flight;
/// - rapid multi-edit turns;
/// - seeded random sequences (strict; residuals are reported and classified).
///
/// Opt-in (`MACDOWN_NEON_RESOLVE_TRIAL=1`); they expect the stage C2 stack wired
/// through `MACDOWN_DEP_TRIAL_ROOT`. Knobs:
/// - `MACDOWN_NEON_RES_SEQUENCES` (default 200), `MACDOWN_NEON_RES_SEED_BASE` (default 1),
///   `MACDOWN_NEON_RES_SEEDS=3,17` (only those seeds)
/// - `MACDOWN_NEON_RES_WIDENED=1` also runs random sequences through ``EditWideningStorageDelegate``
///   (`MACDOWN_NEON_RES_WIDENED_SEQUENCES`, default 50)
/// - `MACDOWN_NEON_RES_RANDOM=0` skips the random sequences
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_RESOLVE_TRIAL"] == "1"))
struct NeonSublayerResolveTests {
    typealias Edit = NeonBufferedInvalidationTests.Edit

    static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024)
    static let block = StallFixtures.block as NSString
    static let blockLength = block.length
    static var blockCount: Int { (text as NSString).length / blockLength }
    static var middleBlock: Int { blockCount / 2 }

    /// Offset of `needle` inside block `k`.
    static func at(_ needle: String, block k: Int = middleBlock, plus: Int = 0) -> Int {
        let range = block.range(of: needle)
        precondition(range.location != NSNotFound, needle)
        return k * blockLength + range.location + plus
    }

    /// The range of `needle` inside block `k`.
    static func range(of needle: String, block k: Int = middleBlock) -> NSRange {
        NSRange(location: at(needle, block: k), length: (needle as NSString).length)
    }

    // MARK: - Editor harness (the app's NeonSyntaxHighlighter -> TextViewHighlighter path)

    enum Between {
        /// Wait until highlighting has gone quiet.
        case quiet
        /// Let the main run loop turn once (Neon's async flush runs) but do not wait for background parses.
        case turn
    }

    struct Outcome {
        let differing: Int
        let first: Int?
        let afterInvalidateAll: Bool?
        let detail: String
    }

    private static func signatures(_ editor: HighlightedEditor) -> [String] {
        let length = (editor.textView.string as NSString).length
        var signatures = [String](repeating: "", count: length)
        for run in editor.renderedRuns() {
            let upper = min(NSMaxRange(run.range), length)
            guard run.range.location < upper else { continue }
            for index in run.range.location ..< upper {
                signatures[index] = run.signature
            }
        }
        return signatures
    }

    /// Applies each group of edits in one main-actor turn, separated by `between`,
    /// waits for highlighting to settle and compares with a fresh highlighter.
    static func run(_ turns: [[Edit]], between: Between = .quiet, widensEdits: Bool = false) async throws -> Outcome {
        let editor = HighlightedEditor(text: text, widensEdits: widensEdits)
        try #require(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let settle: Duration = widensEdits ? .seconds(2) : .milliseconds(800)
        for (index, turn) in turns.enumerated() {
            for edit in turn {
                edit.apply(to: editor.textView)
            }
            guard index + 1 < turns.count else { break }
            switch between {
            case .quiet:
                try #require(await editor.waitUntilQuiet(quietPeriod: settle))
            case .turn:
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        try #require(await editor.waitUntilQuiet(quietPeriod: settle))
        let fresh = HighlightedEditor(text: editor.textView.string)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(800)))
        let expected = signatures(fresh)
        var actual = signatures(editor)
        if actual != expected {
            // Rule out a slow settle before calling it a divergence.
            try? await Task.sleep(for: .seconds(2))
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(2))
            actual = signatures(editor)
        }
        let differing = actual.indices.filter { actual[$0] != expected[$0] }
        guard let first = differing.first else {
            return Outcome(differing: 0, first: nil, afterInvalidateAll: nil, detail: "")
        }
        let string = editor.textView.string as NSString
        let lo = max(0, first - 20), hi = min(string.length, first + 40)
        let near = string.substring(with: NSRange(location: lo, length: hi - lo)).replacingOccurrences(of: "\n", with: "\\n")
        let last = differing.last ?? first
        let detail = "first=\(first) last=\(last) edited='\(actual[first])' fresh='\(expected[first])' near='\(near)'"
        editor.highlighter.invalidateAll()
        _ = await editor.waitUntilQuiet(quietPeriod: .seconds(2))
        return Outcome(differing: differing.count, first: first, afterInvalidateAll: signatures(editor) == expected, detail: detail)
    }

    static func describe(_ outcome: Outcome) -> String {
        var line = "differingUnits=\(outcome.differing)"
        if let equal = outcome.afterInvalidateAll {
            line += " afterInvalidateAll=\(equal ? "fresh" : "differs")"
        }
        return line + (outcome.detail.isEmpty ? "" : " " + outcome.detail)
    }

    private func check(_ name: String, _ turns: [[Edit]], between: Between = .quiet, widensEdits: Bool = false) async throws {
        let outcome = try await Self.run(turns, between: between, widensEdits: widensEdits)
        let edits = turns.map { $0.map(\.description).joined(separator: "; ") }.joined(separator: " | ")
        print("H5-RES case=\(name) \(Self.describe(outcome)) edits=[\(edits)]")
        #expect(outcome.differing == 0, "\(name): \(outcome.differing) units differ from a fresh highlighter")
    }

    private func check(_ name: String, _ edit: Edit) async throws {
        try await check(name, [[edit]])
    }

    // MARK: - Single interior edits, inside and across block boundaries

    @Test func replaceInsideAParagraph() async throws {
        try await check("replaceInsideParagraph", .replace(Self.range(of: "text and a"), "`x` and *y* and"))
    }

    @Test func replaceAcrossABlockBoundary() async throws {
        // from inside the paragraph into the first list item
        let start = Self.at("here.")
        let end = Self.at("one with")
        try await check("replaceAcrossBoundary", .replace(NSRange(location: start, length: end - start), " **joined** "))
    }

    @Test func replace600UnitsWithInlineText() async throws {
        let start = Self.at("text and a")
        try await check("replace600", .replace(NSRange(location: start, length: 600), "replacement with `code` and *em* "))
    }

    /// The stage-2 case (`NeonReplacementEditTests`): the old text with one character added, over whole inline ranges.
    @Test func replaceASelectionContainingInlineRanges() async throws {
        let range = NSRange(location: (Self.text as NSString).length / 2, length: 600)
        try await check("replaceSelectionSameTextPlusY", .replace(range, (Self.text as NSString).substring(with: range) + "y"))
    }

    /// The same selection replaced by its text with the inline markup characters removed.
    @Test func replaceASelectionRemovingItsInlineMarkup() async throws {
        let range = NSRange(location: (Self.text as NSString).length / 2, length: 600)
        var plain = (Self.text as NSString).substring(with: range)
        for markup in ["*", "`", "[", "]"] {
            plain = plain.replacingOccurrences(of: markup, with: "x")
        }
        try await check("replaceSelectionMarkupRemoved", .replace(range, plain))
    }

    @Test func deleteInsideAParagraph() async throws {
        try await check("deleteInsideParagraph", .delete(NSRange(location: Self.at("text and a"), length: 5)))
    }

    @Test func deleteAcrossABlockBoundary() async throws {
        // from inside the heading into the paragraph
        let start = Self.at("with `code`")
        let end = Self.at("*emphasis*", plus: 3)
        try await check("deleteAcrossBoundary", .delete(NSRange(location: start, length: end - start)))
    }

    @Test func insertInsideAParagraph() async throws {
        try await check("insertInsideParagraph", .insert("**new** `c` ", at: Self.at("text and a")))
    }

    @Test func insertABlockBoundaryInsideAParagraph() async throws {
        try await check("insertSplitParagraph", .insert("\n\n# New *heading*\n\n", at: Self.at("text and a")))
    }

    // MARK: - Deleted markup with no replacement range

    @Test func deleteAWholeEmphasis() async throws {
        try await check("deleteEmphasis", .delete(Self.range(of: "*emphasis*")))
    }

    @Test func deleteAWholeLink() async throws {
        try await check("deleteLink", .delete(Self.range(of: "[link](https://example.com)")))
    }

    @Test func deleteAWholeCodeSpan() async throws {
        try await check("deleteCodeSpan", .delete(Self.range(of: "`code`")))
    }

    @Test func deleteAWholeFencedBlock() async throws {
        try await check("deleteFencedBlock", .delete(Self.range(of: "```\nfenced code line\n```\n")))
    }

    @Test func deleteAWholeParagraph() async throws {
        try await check("deleteParagraph", .delete(Self.range(of: "Some *emphasis*, **strong** text and a [link](https://example.com) here.\n\n")))
    }

    @Test func joinAParagraphWithTheFollowingList() async throws {
        try await check("joinParagraphAndList", .delete(Self.range(of: "\n\n- list item one")))
    }

    @Test func joinTheHeadingWithTheParagraph() async throws {
        try await check("joinHeadingAndParagraph", .delete(Self.range(of: "\n\nSome")))
    }

    /// The injection disappears without any replacement: everything after the
    /// new fence becomes fenced code (no inline sublayer ranges there).
    @Test func openAFenceBeforeAParagraph() async throws {
        try await check("openFence", .insert("```\n", at: Self.at("Some *emphasis*")))
    }

    /// The inverse: removing an opening fence turns fenced code into paragraphs.
    @Test func removeAnOpeningFence() async throws {
        try await check("removeOpeningFence", .delete(Self.range(of: "```\nfenced")))
    }

    // MARK: - Stage C1 residuals and the re-entrant flush

    /// C1 residual: deleting whole blocks at a block boundary (28 units in C1).
    @Test func wholeBlockDeletionAtABlockBoundary() async throws {
        try await check("residualWholeBlockDeletion", .delete(NSRange(location: 2 * Self.blockLength, length: 3 * Self.blockLength)))
    }

    /// C1 residual: typing in the last fenced code line leaves its closing fence stale (3 units in C1).
    @Test func typingInTheLastFencedCodeLine() async throws {
        let line = Self.block.range(of: "fenced code line")
        let last = Self.blockCount - 1
        try await check("residualTypingInLastFence", .insert(" **strong** tail", at: last * Self.blockLength + line.location + 9))
    }

    // MARK: - Large (background-parsed) edits followed by more edits

    static var pasteText: String {
        String(repeating: "Pasted *em* and `code` with **strong** [l](https://e.x).\n\n", count: 45)
    }

    @Test func largePasteThenEditsInTheSameTurn() async throws {
        let paste = Self.pasteText
        #expect((paste as NSString).length >= 2048)
        let p = Self.at("text and a")
        try await check("largePasteThenSameTurn", [[
            .insert(paste, at: p),
            .insert("x", at: Self.at("text and a", block: 1)),
            .delete(NSRange(location: Self.at("text and a", block: Self.blockCount - 2), length: 8)),
        ]])
    }

    @Test func largeDeletionThenEditsWhileTheParseIsInFlight() async throws {
        let p = Self.at("text and a")
        try await check("largeDeleteThenTurns", [
            [.delete(NSRange(location: p, length: 3000)), .insert("**b** ", at: p)],
            [.insert("*i* ", at: Self.at("text and a", block: 2))],
            [.replace(NSRange(location: Self.at("text and a", block: Self.blockCount - 20), length: 4), "`k`")],
        ], between: .turn)
    }

    @Test func largeReplacementRemovingMarkupThenEdits() async throws {
        let p = Self.at("text and a")
        try await check("largeReplacePlainThenTurns", [
            [.replace(NSRange(location: p, length: 2500), String(repeating: "plain words ", count: 30))],
            [.insert("x", at: p + 3)],
            [.delete(NSRange(location: p + 1, length: 2))],
        ], between: .turn)
    }

    @Test func largePasteOfAFenceThenEdits() async throws {
        let fence = "```\n" + String(repeating: "code *not em*\n", count: 160) + "```\n"
        let p = Self.at("Some *emphasis*")
        try await check("largePasteFenceThenTurns", [
            [.insert(fence, at: p)],
            [.insert("y", at: p + 2)],
        ], between: .turn)
    }

    // MARK: - Rapid multi-edit turns

    @Test func fortyEditsInOneTurn() async throws {
        var edits: [Edit] = []
        let positions = [Self.at("text and a", block: 3), Self.at("text and a"), Self.at("item two", block: Self.blockCount - 3)]
        var shift = 0
        for step in 0 ..< 40 {
            let slot = step % 3
            let base = positions[slot] + (slot == 0 ? 0 : shift)
            if step % 5 == 4 {
                edits.append(.delete(NSRange(location: base, length: 1)))
                if slot == 0 { shift -= 1 }
            } else {
                edits.append(.insert(["*", "x", "`", " "][step % 4], at: base))
                if slot == 0 { shift += 1 }
            }
        }
        try await check("fortyEditsOneTurn", [edits])
    }

    @Test func tenTurnsOfFiveEditsWithoutWaiting() async throws {
        var turns: [[Edit]] = []
        for turn in 0 ..< 10 {
            let p = Self.at("text and a", block: 5 + turn * 7)
            turns.append([
                .insert("**", at: p),
                .insert("b", at: p + 2),
                .insert("**", at: p + 3),
                .delete(NSRange(location: p + 5, length: 2)),
                .insert("\n\n", at: p + 5),
            ])
        }
        try await check("tenTurnsNoWait", turns, between: .turn)
    }

    // MARK: - Scrolling: the sublayer valid set split by the visible ranges (client level)

    /// TreeSitterClient on a plain NSTextStorage (no TextViewHighlighter), as
    /// the app configures it. Only the queried ("visible") windows are styled,
    /// so only they are resolved; the sublayer validator's valid set is split.
    @MainActor
    final class ClientHarness {
        final class Revision {
            var value: UInt64 = 0
        }

        let textView = NSTextView()
        private let revision = Revision()
        var client: TreeSitterClient!

        init(text: String) throws {
            textView.string = text
            let registry = GrammarRegistry()
            guard let config = registry.configuration(for: "markdown") else { throw CocoaError(.featureUnsupported) }
            // strong captures: Neon's background work may outlive a harness
            let textView = textView, revision = revision
            let transform = NeonSyntaxHighlighter.locationTransformer(for: textView) { revision.value }
            client = try TreeSitterClient(
                rootLanguageConfig: config,
                configuration: .init(
                    languageProvider: registry.languageProvider,
                    contentSnapshopProvider: { limit in .init(string: textView.string, limit: limit) },
                    lengthProvider: { (textView.string as NSString).length },
                    invalidationHandler: { _ in },
                    locationTransformer: transform
                )
            )
        }

        var length: Int { (textView.string as NSString).length }

        /// TextViewHighlighter's order (`textStorage(_:willProcessEditing:)`) instead of the documented one.
        var textViewHighlighterOrder = false

        func apply(_ edit: Edit) {
            let delta = (edit.text as NSString).length - edit.range.length
            if textViewHighlighterOrder {
                // willProcessEditing runs after the characters changed, with the post-change range
                textView.textStorage?.replaceCharacters(in: edit.range, with: edit.text)
                revision.value &+= 1
                client.willChangeContent(in: NSRange(location: edit.range.location, length: (edit.text as NSString).length))
            } else {
                // The documented contract: before the change, with the range being replaced.
                client.willChangeContent(in: edit.range)
                textView.textStorage?.replaceCharacters(in: edit.range, with: edit.text)
                revision.value &+= 1
            }
            client.didChangeContent(in: edit.range, delta: delta)
        }

        /// Highlight capture names per UTF-16 unit of `window`, order-independent,
        /// once they are stable: a query can run before the sublayer resolution it
        /// started (asynchronously) has finished, like Neon's first styling pass.
        func captures(in window: NSRange) async throws -> [String] {
            var previous = try await query(window)
            for _ in 0 ..< 40 {
                try await Task.sleep(for: .milliseconds(50))
                let current = try await query(window)
                if current == previous {
                    return current
                }
                previous = current
            }
            return previous
        }

        private func query(_ window: NSRange) async throws -> [String] {
            let window = NSIntersectionRange(window, NSRange(location: 0, length: length))
            let string = textView.string
            let ranges = try await client.highlights(in: window, provider: string.predicateTextProvider, mode: .required)
            var names = [[String]](repeating: [], count: window.length)
            for named in ranges {
                let r = NSIntersectionRange(named.range, window)
                guard r.length > 0 else { continue }
                for index in r.location ..< NSMaxRange(r) {
                    names[index - window.location].append(named.name)
                }
            }
            return names.map { Set($0).sorted().joined(separator: "+") }
        }
    }

    enum ScrollStep {
        case show(NSRange)
        case edit(Edit)
    }

    /// Runs the steps; after every `show` (and at the end, over the whole document)
    /// compares that window's captures with a fresh client's.
    private func scrollCheck(_ name: String, _ steps: [ScrollStep], textViewHighlighterOrder: Bool = false) async throws {
        let harness = try ClientHarness(text: Self.text)
        harness.textViewHighlighterOrder = textViewHighlighterOrder
        var worst = 0
        var notes: [String] = []
        var keepAlive: [ClientHarness] = []
        func compare(_ window: NSRange, label: String) async throws {
            let actual = try await harness.captures(in: window)
            let fresh = try ClientHarness(text: harness.textView.string)
            keepAlive.append(fresh)
            let expected = try await fresh.captures(in: window)
            let differing = actual.indices.filter { actual[$0] != expected[$0] }
            if let first = differing.first {
                notes.append("\(label)@\(window.location)+\(window.length): \(differing.count) (first=\(window.location + first) edited='\(actual[first])' fresh='\(expected[first])')")
            }
            worst = max(worst, differing.count)
        }
        for (index, step) in steps.enumerated() {
            switch step {
            case let .show(window):
                try await compare(window, label: "step\(index)")
            case let .edit(edit):
                harness.apply(edit)
            }
        }
        try await compare(NSRange(location: 0, length: harness.length), label: "whole")
        try await Task.sleep(for: .milliseconds(200))
        keepAlive.removeAll()
        print("H5-RES case=\(name) worstWindowUnits=\(worst) \(notes.joined(separator: "; "))")
        #expect(worst == 0, "\(name): \(notes.joined(separator: "; "))")
    }

    static let windowA = NSRange(location: 0, length: 6000)
    static let windowB = NSRange(location: 22000, length: 6000)

    @Test func scrollEditInsideAValidatedWindow() async throws {
        let k = 22000 / Self.blockLength + 4
        try await scrollCheck("scrollEditInsideWindow", [
            .show(Self.windowA), .show(Self.windowB),
            .edit(.replace(Self.range(of: "text and a", block: k), "`x` and *y*")),
            .show(Self.windowB),
            .edit(.delete(Self.range(of: "*emphasis*", block: k + 1))),
            .show(Self.windowB),
        ])
    }

    @Test func scrollEditInTheUnvalidatedGapThenScrollThere() async throws {
        let k = 12000 / Self.blockLength
        try await scrollCheck("scrollEditInGap", [
            .show(Self.windowA), .show(Self.windowB),
            .edit(.insert("```\n", at: Self.at("Some *emphasis*", block: k))),
            .show(Self.windowA), .show(Self.windowB),
            .show(NSRange(location: 9000, length: 6000)),
        ])
    }

    @Test func scrollEditStraddlingAWindowBoundary() async throws {
        try await scrollCheck("scrollEditStraddlingBoundary", [
            .show(Self.windowA), .show(Self.windowB),
            .edit(.delete(NSRange(location: Self.windowB.location - 150, length: 300))),
            .show(NSRange(location: Self.windowB.location - 3000, length: 6000)),
            .edit(.replace(NSRange(location: NSMaxRange(Self.windowA) - 40, length: 80), "**x** `y`\n\n- z\n")),
            .show(Self.windowA),
            .show(NSRange(location: 3000, length: 6000)),
        ])
    }

    @Test func scrollWhileEditing() async throws {
        let kB = 22000 / Self.blockLength + 2
        try await scrollCheck("scrollWhileEditing", [
            .show(Self.windowA),
            .edit(.insert("*a* ", at: Self.at("text and a", block: 3))),
            .show(Self.windowB),
            .edit(.delete(Self.range(of: "[link](https://example.com)", block: kB))),
            .show(NSRange(location: 20000, length: 6000)),
            .edit(.delete(Self.range(of: "```\nfenced code line\n```\n", block: kB + 1))),
            .edit(.insert("\n\n", at: Self.at("text and a", block: kB + 3))),
            .show(NSRange(location: 25000, length: 6000)),
            .show(Self.windowA),
        ])
    }

    @Test func scrollLargeEditOutsideTheWindows() async throws {
        let k = 12000 / Self.blockLength
        try await scrollCheck("scrollLargeEditOutside", [
            .show(Self.windowA), .show(Self.windowB),
            .edit(.replace(NSRange(location: Self.at("text and a", block: k), length: 2600), Self.pasteText)),
            .show(Self.windowB), .show(Self.windowA),
        ])
    }

    // MARK: - Client level, whole document: separates edit-point effects from styling

    static let whole = NSRange(location: 0, length: 60000)

    static let clientCases: [(String, Edit)] = [
        ("deleteParagraph", .delete(range(of: "Some *emphasis*, **strong** text and a [link](https://example.com) here.\n\n"))),
        ("wholeBlockDeletion", .delete(NSRange(location: 2 * blockLength, length: 3 * blockLength))),
        ("typingInLastFence", .insert(" **strong** tail", at: (blockCount - 1) * blockLength + block.range(of: "fenced code line").location + 9)),
        ("insertSplitParagraph", .insert("\n\n# New *heading*\n\n", at: at("text and a"))),
        ("openFence", .insert("```\n", at: at("Some *emphasis*"))),
        ("removeOpeningFence", .delete(range(of: "```\nfenced"))),
    ]

    @Test(arguments: 0 ..< 6)
    func clientWholeDocument(index: Int) async throws {
        let (name, edit) = Self.clientCases[index]
        try await scrollCheck("client-\(name)", [.show(Self.whole), .edit(edit)])
        try await scrollCheck("client-tvhOrder-\(name)", [.show(Self.whole), .edit(edit)], textViewHighlighterOrder: true)
    }

    // MARK: - Seeded random sequences (strict)

    private static func seeds(_ countKey: String, default defaultCount: Int) -> [UInt64] {
        let env = ProcessInfo.processInfo.environment
        if let list = env["MACDOWN_NEON_RES_SEEDS"] {
            return list.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        }
        let count = env[countKey].flatMap(Int.init) ?? defaultCount
        let base = env["MACDOWN_NEON_RES_SEED_BASE"].flatMap(UInt64.init) ?? 1
        return (0 ..< UInt64(count)).map { base + $0 }
    }

    /// Every sequence is applied in one turn. A failing sequence is classified:
    /// - `styling`: the edited editor equals a fresh one after `invalidateAll()`
    ///   (its parse state is right; stale styling);
    /// - `artefact`: it is fresh-equal when the same sequence is run again;
    /// - `tree`: otherwise (the parse state / included ranges differ).
    private func random(widened: Bool, countKey: String, defaultCount: Int) async throws {
        var classes: [String: [UInt64]] = [:]
        var units: [UInt64: Int] = [:]
        let seeds = Self.seeds(countKey, default: defaultCount)
        for seed in seeds {
            let edits = NeonBufferedInvalidationTests.sequence(seed: seed, documentLength: (Self.text as NSString).length)
            let outcome = try await Self.run([edits], widensEdits: widened)
            guard outcome.differing > 0 else { continue }
            let kind: String
            if outcome.afterInvalidateAll == true {
                kind = "styling"
            } else if try await Self.run([edits], widensEdits: widened).differing == 0 {
                kind = "artefact"
            } else {
                kind = "tree"
            }
            classes[kind, default: []].append(seed)
            units[seed] = outcome.differing
            print("H5-RES random seed=\(seed) widened=\(widened) class=\(kind) \(Self.describe(outcome)) edits=[\(edits.map(\.description).joined(separator: "; "))]")
        }
        let failing = classes.values.reduce(0) { $0 + $1.count }
        let summary = ["tree", "styling", "artefact"].map { "\($0)=\(classes[$0]?.count ?? 0)\(classes[$0].map { "\($0)" } ?? "[]")" }
        print("H5-RES-SUMMARY widened=\(widened) sequences=\(seeds.count) failing=\(failing) \(summary.joined(separator: " ")) units=\(units.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })")
        #expect(failing == 0, "\(failing) of \(seeds.count) random sequences differ from a fresh highlighter")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_RES_RANDOM"] != "0"))
    func randomSequencesEqualAFreshHighlighter() async throws {
        try await random(widened: false, countKey: "MACDOWN_NEON_RES_SEQUENCES", defaultCount: 200)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_RES_WIDENED"] == "1"))
    func randomWidenedSequencesEqualAFreshHighlighter() async throws {
        try await random(widened: true, countKey: "MACDOWN_NEON_RES_WIDENED_SEQUENCES", defaultCount: 50)
    }
}
