import AppKit
import Foundation
@testable import Highlighting
import Testing

/// DEP-TRIAL ONLY (stage C1, `planning/downstream/evidence/h5-neon-invalidation/`).
///
/// Neon's `TextViewHighlighter` buffers invalidations until an async main-queue
/// turn. These tests make several edits in one main-actor turn, before that
/// turn runs, and compare the final rendering attributes with a fresh
/// highlighter's for every UTF-16 unit. Stock Neon 484d6fb9 fails them because
/// the buffered set is not moved through the later edits.
///
/// - The deterministic cases keep the Markdown block structure (inline-only
///   edits inside paragraphs, whole-block deletions and insertions), so the
///   separate missing-sublayer-resolution bug cannot contribute. They require
///   equality with a fresh highlighter.
/// - The random sequences also change blocks. Each failing sequence is re-run
///   as a control with every edit in its own turn (pending updates drained in
///   between). Units the one-turn run gets wrong although the control gets them
///   right are multi-edit (buffering) failures, and only those fail the test.
///   Units the control gets wrong too are reported, not asserted: they are
///   single-edit defects (for example the missing sublayer resolution).
///
/// Opt-in (`MACDOWN_NEON_INVALIDATION_TRIAL=1`); they expect the stage C1 Neon
/// copy wired through `MACDOWN_DEP_TRIAL_ROOT`. Other knobs:
/// - `MACDOWN_NEON_INV_SEQUENCES` (default 200), `MACDOWN_NEON_INV_SEED_BASE` (default 1)
/// - `MACDOWN_NEON_INV_SEEDS=3,17` runs only those seeds
/// - `MACDOWN_NEON_INV_WIDENED=1` also runs the random sequences through
///   ``EditWideningStorageDelegate`` (Neon's background path)
/// - `MACDOWN_NEON_INV_EDITS='loc+len=text;...'` runs one ad-hoc sequence
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_INVALIDATION_TRIAL"] == "1"))
struct NeonBufferedInvalidationTests {
    static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024)

    struct Edit: CustomStringConvertible {
        let range: NSRange
        let text: String

        static func insert(_ text: String, at location: Int) -> Edit {
            Edit(range: NSRange(location: location, length: 0), text: text)
        }

        static func delete(_ range: NSRange) -> Edit {
            Edit(range: range, text: "")
        }

        static func replace(_ range: NSRange, _ text: String) -> Edit {
            Edit(range: range, text: text)
        }

        var description: String {
            "\(range.location)+\(range.length)='\(text.replacingOccurrences(of: "\n", with: "\\n"))'"
        }

        func apply(to textView: NSTextView) {
            textView.insertText(text, replacementRange: range)
        }
    }

    struct Outcome {
        let differingUnits: Int
        /// After `invalidateAll()` on the edited editor: true means only the
        /// styling was stale; false means the parse state differs.
        let equalAfterInvalidateAll: Bool?
        let detail: String
        /// Rendering signature per UTF-16 unit, before any `invalidateAll()`, and the fresh highlighter's.
        let edited: [String]
        let fresh: [String]

        /// Units this outcome gets wrong although `control` gets them right.
        func excessUnits(over control: Outcome) -> Int {
            guard edited.count == control.edited.count, fresh == control.fresh else { return max(edited.count, 1) }
            return edited.indices.reduce(0) { $0 + (edited[$1] != fresh[$1] && control.edited[$1] == fresh[$1] ? 1 : 0) }
        }
    }

    // MARK: - Harness

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

    private static func differences(_ a: [String], _ b: [String]) -> (count: Int, first: Int?) {
        guard a.count == b.count else { return (max(a.count, b.count), 0) }
        var count = 0
        var first: Int?
        for index in a.indices where a[index] != b[index] {
            count += 1
            if first == nil { first = index }
        }
        return (count, first)
    }

    /// Opens the fixture and applies `edits` synchronously in this turn (or, with
    /// `perTurn`, one per turn with pending updates drained in between), lets
    /// every pending update run, and compares with a fresh highlighter per UTF-16 unit.
    static func run(_ edits: [Edit], widensEdits: Bool = false, perTurn: Bool = false) async throws -> Outcome {
        let editor = HighlightedEditor(text: text, widensEdits: widensEdits)
        try #require(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let settle: Duration = widensEdits ? .seconds(2) : .milliseconds(600)

        for edit in edits {
            edit.apply(to: editor.textView)
            if perTurn {
                try #require(await editor.waitUntilQuiet(quietPeriod: settle))
            }
        }

        try #require(await editor.waitUntilQuiet(quietPeriod: settle))
        let fresh = HighlightedEditor(text: editor.textView.string)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(600)))
        let freshSignatures = signatures(fresh)
        var diff = differences(signatures(editor), freshSignatures)
        if diff.count > 0 {
            // Rule out a slow settle before calling it a divergence.
            try? await Task.sleep(for: .seconds(2))
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(2))
            diff = differences(signatures(editor), freshSignatures)
        }
        var detail = ""
        var afterInvalidateAll: Bool?
        let editedSignatures = signatures(editor)
        if diff.count > 0, let first = diff.first {
            let string = editor.textView.string as NSString
            let lo = max(0, first - 20), hi = min(string.length, first + 40)
            let near = string.substring(with: NSRange(location: lo, length: hi - lo))
                .replacingOccurrences(of: "\n", with: "\\n")
            let edited = signatures(editor)
            detail = "first=\(first) edited='\(edited[first])' fresh='\(freshSignatures[first])' near='\(near)'"
            editor.highlighter.invalidateAll()
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(2))
            afterInvalidateAll = signatures(editor) == freshSignatures
        }
        return Outcome(
            differingUnits: diff.count,
            equalAfterInvalidateAll: afterInvalidateAll,
            detail: detail,
            edited: editedSignatures,
            fresh: freshSignatures
        )
    }

    private static func describe(_ outcome: Outcome) -> String {
        var line = "differingUnits=\(outcome.differingUnits)"
        if let equal = outcome.equalAfterInvalidateAll {
            line += " afterInvalidateAll=\(equal ? "fresh" : "differs")"
        }
        return line
    }

    private static func report(_ name: String, _ edits: [Edit], _ outcome: Outcome, control: Outcome? = nil) {
        var line = "H5-INV case=\(name) \(describe(outcome))"
        if let control {
            line += " control[\(describe(control))] excessUnits=\(outcome.excessUnits(over: control))"
        }
        if !outcome.detail.isEmpty {
            line += " \(outcome.detail)"
        }
        line += " edits=[\(edits.map(\.description).joined(separator: "; "))]"
        print(line)
    }

    private func check(_ name: String, _ edits: [Edit]) async throws {
        let outcome = try await Self.run(edits)
        let control = outcome.differingUnits > 0 ? try await Self.run(edits, perTurn: true) : nil
        Self.report(name, edits, outcome, control: control)
        #expect(outcome.differingUnits == 0, "\(name): \(outcome.differingUnits) units differ from a fresh highlighter")
    }

    // MARK: - Fixture geometry

    private static let blockLength = StallFixtures.block.utf16.count
    private static var blockCount: Int { text.utf16.count / blockLength }
    /// Inside the paragraph of block `k`: the "t" of "text and a [link]".
    private static func paragraph(_ k: Int) -> Int {
        let offset = (StallFixtures.block as NSString).range(of: " text and").location + 1
        return k * blockLength + offset
    }
    /// `count` blocks' worth of text starting inside the paragraph of block `k`.
    /// The result equals deleting whole blocks, but the edit does not start at a
    /// block boundary (whole-block deletions hit a separate single-edit defect;
    /// see `residualWholeBlockDeletion`).
    private static func blocksFromParagraph(_ k: Int, count: Int = 1) -> NSRange {
        NSRange(location: paragraph(k), length: count * blockLength)
    }
    private static var middleBlock: Int { blockCount / 2 }
    private static var lastBlock: Int { blockCount - 1 }

    // MARK: - Deterministic sequences (block structure unchanged)

    /// The NeonReplacementEditTests scenario: type in the middle, then delete a block before it, in one turn.
    @Test func typeInTheMiddleThenDeleteABlockBeforeIt() async throws {
        let middle = Self.text.utf16.count / 2
        var edits: [Edit] = []
        for index in 0 ..< 11 {
            edits.append(index.isMultiple(of: 2) ? .insert("x", at: middle) : .delete(NSRange(location: middle, length: 1)))
        }
        edits.append(.delete(NSRange(location: 1000, length: 1500)))
        try await check("typeMiddleThenDeleteBlockBefore", edits)
    }

    @Test func typeInAParagraphThenDeleteWholeBlocksBeforeIt() async throws {
        let p = Self.paragraph(Self.middleBlock)
        var edits: [Edit] = []
        for index in 0 ..< 7 {
            edits.append(index.isMultiple(of: 2) ? .insert("x", at: p) : .delete(NSRange(location: p, length: 1)))
        }
        edits.append(.delete(Self.blocksFromParagraph(2, count: 3)))
        try await check("typeParagraphThenDeleteBlocksBefore", edits)
    }

    @Test func insertInTheMiddleThenAtTheStart() async throws {
        try await check("insertMiddleThenStart", [
            .insert("*em* ", at: Self.paragraph(Self.middleBlock)),
            .insert("lead **x** ", at: Self.paragraph(0)),
        ])
    }

    @Test func insertAtTheEndThenTheMiddleThenTheStart() async throws {
        try await check("insertEndMiddleStart", [
            .insert(" **strong** tail", at: Self.paragraph(Self.lastBlock)),
            .insert(" *em* `code`", at: Self.paragraph(Self.middleBlock)),
            .insert("lead ", at: Self.paragraph(0)),
        ])
    }

    @Test func insertAtTheStartThenTheMiddleThenTheEnd() async throws {
        let first = "lead ", second = " *em* `code`"
        let shift = first.utf16.count + second.utf16.count
        try await check("insertStartMiddleEnd", [
            .insert(first, at: Self.paragraph(0)),
            .insert(second, at: Self.paragraph(Self.middleBlock) + first.utf16.count),
            .insert(" **strong** tail", at: Self.paragraph(Self.lastBlock) + shift),
        ])
    }

    @Test func replaceInTheMiddleThenDeleteABlockBeforeIt() async throws {
        try await check("replaceMiddleThenDeleteBlockBefore", [
            .replace(NSRange(location: Self.paragraph(Self.middleBlock), length: 10), "`code` and *em*"),
            .delete(Self.blocksFromParagraph(3)),
        ])
    }

    @Test func insertABlockAtTheStartAfterAMiddleEdit() async throws {
        try await check("middleEditThenInsertBlockAtStart", [
            .insert("**bold** ", at: Self.paragraph(Self.middleBlock)),
            .insert(StallFixtures.block, at: 0),
        ])
    }

    @Test func typeThenDeleteAcrossTheTypedTextsStart() async throws {
        // The deletion removes the front of the range the typing invalidated; its tail survives.
        let p = Self.paragraph(Self.middleBlock)
        try await check("typeThenDeleteOverlappingFront", [
            .insert("**bold**", at: p),
            .delete(NSRange(location: p - 15, length: 18)),
        ])
    }

    @Test func typeThenDeleteAcrossTheTypedTextsEnd() async throws {
        let p = Self.paragraph(Self.middleBlock)
        try await check("typeThenDeleteOverlappingEnd", [
            .insert("`code` here", at: p),
            .delete(NSRange(location: p + 6, length: 20)),
        ])
    }

    @Test func deleteAtTheEndThenReplaceAtTheStartThenTypeInTheMiddle() async throws {
        let shiftBeforeMiddle = "Changed `x`".utf16.count - 7
        try await check("deleteEndReplaceStartTypeMiddle", [
            .delete(Self.blocksFromParagraph(Self.lastBlock - 1)),
            .replace(NSRange(location: Self.paragraph(0), length: 7), "Changed `x`"),
            .insert("y", at: Self.paragraph(Self.middleBlock) + shiftBeforeMiddle),
            .insert("y", at: Self.paragraph(Self.middleBlock) + shiftBeforeMiddle),
        ])
    }

    @Test func manySmallEditsWalkingBackwards() async throws {
        var edits: [Edit] = []
        var k = Self.lastBlock
        var step = 0
        while k > 0 {
            let p = Self.paragraph(k)
            edits.append(step.isMultiple(of: 3) ? .delete(NSRange(location: p, length: 2)) : .insert("*z*", at: p))
            k -= 17
            step += 1
        }
        try await check("walkBackwards", edits)
    }

    // MARK: - Residual single-edit defects (reported, not part of the patch)

    /// One edit, so buffering cannot be involved: deleting whole blocks leaves the
    /// fenced block before the deletion point styled like the heading after it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_INV_RESIDUALS"] == "1"))
    func residualWholeBlockDeletion() async throws {
        try await check("residualWholeBlockDeletion", [
            .delete(NSRange(location: 2 * Self.blockLength, length: 3 * Self.blockLength)),
        ])
    }

    /// One edit: typing inside the last fenced code line leaves its closing fence stale.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_INV_RESIDUALS"] == "1"))
    func residualTypingInTheLastFencedCodeLine() async throws {
        let line = (StallFixtures.block as NSString).range(of: "fenced code line")
        try await check("residualTypingInLastFence", [
            .insert(" **strong** tail", at: Self.lastBlock * Self.blockLength + line.location + 9),
        ])
    }

    // MARK: - Randomized sequences

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let inlineSnippets = ["x", "abc ", "*em*", "**strong**", "`code`", "[l](https://e.x)", " plain words "]
    static let blockSnippets = ["\n", "\n\n- item\n", "\n```\nfence\n```\n", "\n# H\n", "\n> q\n"]

    /// 2-6 inserts, deletions and replacements at the start, middle, end or anywhere.
    static func sequence(seed: UInt64, documentLength: Int) -> [Edit] {
        var rng = SplitMix64(state: seed)
        var length = documentLength
        var edits: [Edit] = []
        for _ in 0 ..< Int.random(in: 2 ... 6, using: &rng) {
            let location: Int
            switch Int.random(in: 0 ..< 4, using: &rng) {
            case 0: location = Int.random(in: 0 ... min(200, length), using: &rng)
            case 1: location = Int.random(in: max(0, length / 2 - 300) ... min(length, length / 2 + 300), using: &rng)
            case 2: location = Int.random(in: max(0, length - 200) ... length, using: &rng)
            default: location = Int.random(in: 0 ... length, using: &rng)
            }
            let deleteLength = min(length - location, Bool.random(using: &rng)
                ? Int.random(in: 1 ... 40, using: &rng)
                : Int.random(in: 1 ... 1800, using: &rng))
            let block = Int.random(in: 0 ..< 4, using: &rng) == 0
            let snippet = block ? blockSnippets.randomElement(using: &rng)! : inlineSnippets.randomElement(using: &rng)!
            let edit: Edit
            switch Int.random(in: 0 ..< 3, using: &rng) {
            case 0: edit = .insert(snippet, at: location)
            case 1 where deleteLength > 0: edit = .delete(NSRange(location: location, length: deleteLength))
            default: edit = .replace(NSRange(location: location, length: deleteLength), snippet)
            }
            edits.append(edit)
            length += edit.text.utf16.count - edit.range.length
        }
        return edits
    }

    private static func seeds() -> [UInt64] {
        let env = ProcessInfo.processInfo.environment
        if let list = env["MACDOWN_NEON_INV_SEEDS"] {
            return list.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        }
        let count = env["MACDOWN_NEON_INV_SEQUENCES"].flatMap(Int.init) ?? 200
        let base = env["MACDOWN_NEON_INV_SEED_BASE"].flatMap(UInt64.init) ?? 1
        return (0 ..< UInt64(count)).map { base + $0 }
    }

    private func randomSequences(widensEdits: Bool) async throws {
        var oneTurnFailures: [UInt64] = []
        var multiEdit: [UInt64] = []
        var singleEdit: [UInt64] = []
        let seeds = Self.seeds()
        for seed in seeds {
            let edits = Self.sequence(seed: seed, documentLength: Self.text.utf16.count)
            let outcome = try await Self.run(edits, widensEdits: widensEdits)
            guard outcome.differingUnits > 0 else { continue }
            oneTurnFailures.append(seed)
            let control = try await Self.run(edits, widensEdits: widensEdits, perTurn: true)
            let excess = outcome.excessUnits(over: control)
            if excess > 0 {
                multiEdit.append(seed)
            } else {
                singleEdit.append(seed)
            }
            Self.report("random seed=\(seed) widened=\(widensEdits) kind=\(excess > 0 ? "multiEdit" : "controlFailsToo")", edits, outcome, control: control)
        }
        print("H5-INV-SUMMARY widened=\(widensEdits) sequences=\(seeds.count) oneTurnFailing=\(oneTurnFailures.count) multiEdit=\(multiEdit.count) controlFailsToo=\(singleEdit.count) multiEditSeeds=\(multiEdit) controlFailsTooSeeds=\(singleEdit)")
        #expect(multiEdit.isEmpty, "\(multiEdit.count) of \(seeds.count) sequences get units wrong in one turn that their one-edit-per-turn control gets right")
    }

    @Test func randomSequencesMatchTheirOneEditPerTurnControl() async throws {
        try await randomSequences(widensEdits: false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_INV_WIDENED"] == "1"))
    func randomWidenedSequencesMatchTheirOneEditPerTurnControl() async throws {
        try await randomSequences(widensEdits: true)
    }

    /// Ad-hoc reproduction: `MACDOWN_NEON_INV_EDITS='24667+0=x;1000+1500='` (location+length=text, `\n` escaped).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_INV_EDITS"] != nil))
    func customSequence() async throws {
        let env = ProcessInfo.processInfo.environment
        let edits: [Edit] = (env["MACDOWN_NEON_INV_EDITS"] ?? "").split(separator: ";").compactMap { item in
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let range = parts[0].split(separator: "+").compactMap { Int($0) }
            guard range.count == 2 else { return nil }
            let text = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "\\n", with: "\n") : ""
            return .replace(NSRange(location: range[0], length: range[1]), text)
        }
        let widened = env["MACDOWN_NEON_INV_WIDENED"] == "1"
        let outcome = try await Self.run(edits, widensEdits: widened, perTurn: env["MACDOWN_NEON_INV_PER_TURN"] == "1")
        Self.report("custom widened=\(widened)", edits, outcome)
        #expect(outcome.differingUnits == 0)
    }
}
