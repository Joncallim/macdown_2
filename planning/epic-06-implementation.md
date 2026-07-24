# EPIC-06 Implementation Plan — Markdown engine: swift-markdown parse actor, debounce, front matter, source-range index

> **Issue:** #7 — [EPIC-06] Markdown engine
> **High-level spec:** `planning/epics/EPIC-06-markdown-engine.md` (scope/acceptance are binding, including the #28 amendments).
> **Branch:** `epic/06-markdown-engine` → PR into `master`.
> **Depends on:** E01 only (`FileCore` — and even that dependency is *removed* here, see §6). E04/E05 are not touched.
> **Intended pipeline:** implemented by **Kimi K2.7**, reviewed by **DeepSeek**. Written so that **neither has to guess intent or fill gaps.** Read **§2 (native-first stance)**, **§3 (decisions)**, and **§4.2 (API contract)** before writing code — reviews reject on §3 and §4.
>
> **New third-party dependencies (both pinned, both wrapped):** `swiftlang/swift-markdown` (Apache-2.0) and `jpsim/Yams` (MIT). Neither type from either library appears in any public signature (§3.D1, §3.D3) per `AGENTS.md`.

---

## 1. Ground rules (binding, carried from E00–E05)

1. **macOS 26.0 only. No availability checks.** Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings.
2. **Package holds the logic; the app holds glue.** This epic is **package-only**: no app-target changes at all (§4.9). The engine is pure (`String` in → `MarkdownDocument` out) and fully testable headless.
3. **The engine replaces the EPIC-02 placeholder outright.** Nothing in the placeholder (`renderAttributed`) constrains this design. The placeholder function is *kept but quarantined* (§3.D6) because the placeholder `Preview` still calls it until E07.
4. **Tests: Swift Testing (`@Test`)** for everything. There is no UI in this epic, so there is no XCUITest component and **every acceptance gate runs under `swift test` in CI** (the `macos-15` runner constraint from E03–E05 is irrelevant here — that is a feature of this epic, use it).
5. **Graceful totality.** The conversion from the third-party AST to our value tree must be *total*: an unrecognised node maps to `.custom(typeName)` — never a crash, never a dropped subtree, never `fatalError`.
6. **Out of scope (hard):** rendering (E07), scroll-sync UI (E07), outline UI (E08), HTML generation (E12 uses swift-cmark directly), settings UI (E13 — defaults are hardcoded here), incremental Markdown parsing (does not exist in swift-markdown; full re-parse is the design, see issue context).
7. **Tabs are native windows (as-built E03).** Engine consumers are per-window: one parse session per open document, torn down with the window. The store in §4.6 mirrors `EditorTextSystemStore`/`SyntaxHighlightStore` exactly for that reason.

---

## 2. Native-first stance (required reading)

| Concern | **Native API to use** | Third-party (only where native is absent) |
|---|---|---|
| Concurrency & debounce | **Swift structured concurrency** — `actor` for the parse owner, `Task` + `Task.sleep(for:)` cancellation-debounce, `@MainActor` for the session. **Not** Combine, **not** `DispatchWorkItem`, **not** timers. | — |
| Observation / reactivity | **Observation framework** (`@Observable`, `@MainActor`) — matches E02–E05. | — |
| Value modelling | **`Codable`-free plain `Sendable` value types** (no persistence need), `Equatable` for test assertions. | — |
| String/line math | **`String.UTF16View`**, `NSString` line APIs are *not* needed — a single manual pass builds the line table (§4.5). | — |
| Timing (perf tests) | **`ContinuousClock`**. | — |
| Markdown parsing (CommonMark + GFM) | *No native equivalent* — `AttributedString(markdown:)` discards source positions and block structure detail; Foundation has no AST API. | **swift-markdown** (cmark-gfm based; retains source ranges). |
| YAML front matter | *No native equivalent* — Foundation has no YAML parser. | **Yams**. |

**Why swift-markdown and not raw cmark-gfm bindings?** swift-markdown is the maintained Swift-native AST layer over cmark-gfm, retains per-node `SourceRange`s (the whole point of this epic — the source-range index), and is already the locked MIGRATION_PLAN §5 selection. Raw cmark would mean hand-rolling node walking + source ranges in C. **Rejected:** `AttributedString(markdown:)` (no block AST, no ranges), MarkdownUI/Textual parsing (rendering libraries, E07's concern, and would invert the dependency direction).

---

## 3. Key architectural decisions (review anchors — do not silently deviate)

### D1 — swift-markdown stays internal; the public surface is our own block-level value tree
`ParseEngine` imports `Markdown` **internally only**. The public API exposes `MarkdownDocument` / `MarkdownBlock` / `HeadingItem` — our own `Sendable` value types (§4.2). **Rationale:** (a) the epic file mandates it ("expose our own `MarkdownDocument` value type so a future parser swap never touches Preview/OutlineUI"); (b) swift-markdown's `Markup` types are **not `Sendable`** and must not cross the actor boundary — conversion happens *inside* the actor; (c) one seam for DeepSeek to audit. **Rejected:** re-exporting `Markdown.Document` (leaks a non-Sendable third-party type into every consumer and violates AGENTS.md wrapping policy).

### D2 — Block-level public AST; inline detail is deliberately withheld
`MarkdownBlock` describes **block structure only** (headings, paragraphs, code blocks, lists, quotes, tables, …) plus each heading's plain-text title. Inline nodes (emphasis, links, inline code) are **not** exposed. **Rationale:** the three consumers need exactly this — E07 renders from the `body` string (Textual consumes Markdown text) and scroll-syncs on block line ranges; E08 needs headings; E12 uses swift-cmark directly. Withheld ≠ forbidden forever: if E07 turns out to need inline nodes, they are added *additively* in that epic. **Rejected:** mirroring the full inline AST now (large surface, zero current consumers, high review cost).

### D3 — Front matter is extracted *before* the Markdown parse; Yams stays internal
The extractor (§4.4) strips a leading `--- … ---` block, records its line span, and hands only the remaining `body` to swift-markdown. Yams parses the raw block into `FrontMatterValue` (our own `Sendable` enum — Yams types never leak). **If the delimiters are present, it IS front matter** even when the YAML inside fails to parse (`values == nil`, raw text preserved). **Rationale:** delimiter-presence semantics are stable while the user is mid-edit — otherwise a half-typed value would make the whole block flicker between "front matter" and "rendered `---` thematic break + paragraph" in the preview on every keystroke. **Rejected:** valid-YAML-only detection (flicker, surprising), post-parse AST surgery (fragile, wrong line numbers).

### D4 — All line numbers are 1-based lines of the ORIGINAL full source; columns are discarded
Every `lineRange` in the public API refers to the original document text (front matter included in the numbering), so editor ↔ engine mapping needs no offset arithmetic in consumers. swift-markdown's columns are UTF-8-based and are **deliberately discarded** — block granularity is whole lines, which is all scroll sync (E07) and outline jumping (E08) need, and it eliminates the UTF-8/UTF-16 column-conversion bug class entirely. `SourceMap` (§4.5) converts lines ↔ UTF-16 offsets for the editor. **Rejected:** exposing column-precise ranges (invites off-by-one column bugs in consumers for zero current benefit).

### D5 — Debounce lives in a `@MainActor` session; parsing lives in an actor; results are revisioned
`MarkdownParseSession` (§4.3) owns the cancel-and-restart debounce `Task` (~150 ms) and publishes `document` via `@Observable`. `ParseEngine` (an `actor`) does the pure work off the main thread. Every parse carries a monotonically increasing `revision`; the session publishes a result only if its revision is newer than the published one (belt-and-braces on top of cancellation — the actor serialises, so this guard is cheap and total). **Rejected:** debouncing inside the actor (cancellation must happen where the keystrokes arrive — on the main actor, with no hop), Combine `debounce` (banned stack).

### D6 — The EPIC-02 placeholder renderer is quarantined, not deleted
`MarkdownEngine.renderAttributed(_:)` moves verbatim into `LegacyPlaceholderRenderer.swift`, marked `@available(*, deprecated, message: "EPIC-02 placeholder; deleted in E07")`. The placeholder `Preview` module still calls it; deleting it would force `Preview` churn that is E07's job. **The deprecation warning must be silenced at the *call site* in `Preview`** with a one-line `// swiftlint:disable` or a wrapper — the package must still build warning-free (ground rule 1). Simplest compliant option: do **not** deprecate formally; mark it `// MARK: - EPIC-02 placeholder (deleted in E07)` with a doc comment. Choose the doc-comment route — zero warnings, zero churn.

### D7 — GFM options are modelled by us, mapped best-effort onto swift-markdown
`MarkdownParseOptions` (§4.2) records the five epic-mandated toggles (tables, task lists, strikethrough, autolinks, footnotes). swift-markdown enables the GFM extension set as a whole and may not expose per-extension switches; whichever toggles cannot actually be turned off are documented as **always-on, flag recorded for E12/E13 intent** — the struct is still the right shape for settings (E13) and export (E12) to consume. Verify what 0.8.x supports at implementation time and record findings on the PR (§10.1, §10.2). **Rejected:** blocking the epic on per-extension parity with cmark-gfm.

---

## 4. Architecture

### 4.1 Module boundary & dependency graph

```
MarkdownEngine  (REPLACE placeholder; imports Foundation, Markdown [internal], Yams [internal])
  ├── MarkdownParseOptions   GFM toggle record (D7)
  ├── FrontMatter            raw + lineRange + parsed values (D3)
  ├── FrontMatterValue       Sendable YAML value tree (string/number/bool/array/dictionary/null)
  ├── MarkdownBlock          block-level value tree + BlockKind (D2)
  ├── HeadingItem            level + plain-text title + lineRange (E08's feed)
  ├── SourceMap              1-based line table ↔ UTF-16 offsets (D4)
  ├── MarkdownDocument       the parse result (body, blocks, headings, frontMatter, sourceMap, revision)
  ├── ParseEngine            actor: the only file that imports Markdown/Yams (D1, D3)
  ├── ParseExecuting         protocol seam over the engine (test spies, DeepSeek's audit point)
  ├── MarkdownParseSession   @MainActor @Observable: debounce + publish (D5)
  ├── MarkdownParseStore     @MainActor cache: identity → session (parallels EditorTextSystemStore)
  └── LegacyPlaceholderRenderer  quarantined EPIC-02 renderAttributed (D6)

Depends on:  NOTHING in-package (FileCore dependency is removed — §6)
Consumed by: Preview (placeholder today, E07 for real), OutlineUI (E08), ExportService (E12)
```

Dependency direction: `{Preview, OutlineUI, ExportService} → MarkdownEngine`. `MarkdownEngine` imports **no** sibling module. It has no AppKit import except inside `LegacyPlaceholderRenderer.swift` (which is why that file exists separately — the engine proper is AppKit-free and could run on Linux).

### 4.2 Public API contract — types

```swift
import Foundation

/// GFM feature toggles. Defaults match MacDown behaviour (all on).
/// Which of these swift-markdown can actually disable is recorded on the PR (D7);
/// the struct is the stable shape E12/E13 consume regardless.
public struct MarkdownParseOptions: Sendable, Equatable {
    public var tables: Bool
    public var taskLists: Bool
    public var strikethrough: Bool
    public var autolinks: Bool
    public var footnotes: Bool
    public init(tables: Bool = true, taskLists: Bool = true, strikethrough: Bool = true,
                autolinks: Bool = true, footnotes: Bool = true)
    public static let `default` = MarkdownParseOptions()
}

/// A parsed YAML value. Our own tree — Yams never leaks (D3).
public enum FrontMatterValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([FrontMatterValue])
    case dictionary([String: FrontMatterValue])
    case null
}

/// A leading `--- … ---` block. Present iff the delimiters were found (D3).
public struct FrontMatter: Sendable, Equatable {
    /// Text between the delimiter lines (exclusive), exactly as written.
    public let raw: String
    /// 1-based lines of the ORIGINAL source, INCLUDING both delimiter lines.
    public let lineRange: ClosedRange<Int>
    /// Parsed mapping, or nil when the YAML is malformed or not a mapping.
    public let values: [String: FrontMatterValue]?
}

/// Block kinds. `custom` is the totality escape hatch (ground rule 5).
public enum BlockKind: Sendable, Equatable {
    case heading(level: Int)                  // 1...6
    case paragraph
    case codeBlock(language: String?)         // fenced info-string first word, lowercased; nil for indented/absent
    case blockQuote
    case orderedList(startIndex: Int)
    case unorderedList
    case listItem(taskState: TaskState?)      // nil = plain item
    case table(columnCount: Int)
    case thematicBreak
    case htmlBlock
    case footnoteDefinition(label: String)    // produced only if swift-markdown parses footnotes (D7)
    case custom(String)                       // unmapped Markup type name — never dropped, never a crash

    public enum TaskState: Sendable, Equatable { case checked, unchecked }
}

/// One block node. A value tree — children are copies, no reference semantics.
public struct MarkdownBlock: Sendable, Equatable {
    public let kind: BlockKind
    /// 1-based lines of the ORIGINAL source (D4). Always non-empty, always
    /// within 1...sourceMap.lineCount.
    public let lineRange: ClosedRange<Int>
    public let children: [MarkdownBlock]
}

/// A heading, flattened for E08. `title` is the plain-text inline content
/// (swift-markdown `plainText`), markup stripped.
public struct HeadingItem: Sendable, Equatable {
    public let level: Int                     // 1...6
    public let title: String
    public let lineRange: ClosedRange<Int>    // original-source lines (D4)
}

/// Line ↔ UTF-16 offset conversion for the ORIGINAL source (D4).
/// Built in one O(n) pass; `\n` terminates lines; a `\r` before `\n` belongs
/// to the preceding line's content (offsets count UTF-16 units, so CRLF is
/// handled by construction, not by special cases).
public struct SourceMap: Sendable, Equatable {
    public let lineCount: Int
    /// UTF-16 offset at which each 1-based line starts. `lineStartOffsets[0]`
    /// is line 1 and is always 0. Count == lineCount (empty text ⇒ 1 line, [0]).
    public let lineStartOffsets: [Int]
    /// Total UTF-16 length of the source.
    public let utf16Length: Int

    /// UTF-16 range covering the given original-source lines, clamped to the
    /// document. The range of the last line extends to `utf16Length`.
    public func utf16Range(ofLines lines: ClosedRange<Int>) -> NSRange
    /// 1-based line containing the given UTF-16 offset (binary search).
    /// Offsets ≥ utf16Length return lineCount; negative offsets return 1.
    public func line(atUTF16Offset offset: Int) -> Int
}

/// The complete parse result. Immutable snapshot; a new value per parse.
public struct MarkdownDocument: Sendable, Equatable {
    /// The source WITHOUT the front-matter lines — what E07 hands to the renderer.
    public let body: String
    /// Number of original-source lines occupied by front matter (0 if none).
    /// body's line N == original line N + bodyLineOffset.
    public let bodyLineOffset: Int
    /// Block tree in document order (top-level blocks; children nested).
    public let blocks: [MarkdownBlock]
    /// All headings in document order (flattened from `blocks`).
    public let headings: [HeadingItem]
    public let frontMatter: FrontMatter?
    /// Line table of the ORIGINAL source (front matter included).
    public let sourceMap: SourceMap
    /// The revision passed to the parse that produced this document.
    public let revision: Int
    /// The options the parse ran with.
    public let options: MarkdownParseOptions

    /// Deepest block whose lineRange contains `line`; nil when the line is
    /// blank between blocks or inside front matter. Binary search over
    /// top-level blocks, then linear descent (children counts are small).
    public func block(atLine line: Int) -> MarkdownBlock?
}
```

### 4.3 Public API contract — engine, session, store

```swift
/// The seam (D5). The production conformer is ParseEngine; tests inject spies.
public protocol ParseExecuting: Sendable {
    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument
}

/// The parse owner. An actor so work is serialised and OFF the main thread.
/// The ONLY file that imports Markdown and Yams (D1, D3).
public actor ParseEngine: ParseExecuting {
    public init()
    /// Pure: text in → document out. Phases: front-matter extraction →
    /// swift-markdown parse of body → block/heading/source-map build.
    /// Checks Task.isCancelled BETWEEN phases and throws CancellationError;
    /// the cmark call itself is not interruptible (accepted — it is ms-scale).
    /// Contains `dispatchPrecondition(condition: .notOnQueue(.main))` so the
    /// entire test suite enforces the off-main acceptance criterion.
    public func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument
}

/// Per-document debounce + publish. One per open document, owned via the store.
@MainActor @Observable
public final class MarkdownParseSession {
    /// Latest completed parse. nil until the first parse completes.
    public private(set) var document: MarkdownDocument?
    /// True while a parse Task is pending or running (drives subtle UI later).
    public private(set) var isParsing: Bool
    /// Completed-parse counter — exists for the debounce acceptance test.
    public private(set) var completedParseCount: Int

    /// `debounce` is injectable so tests run fast; production uses the default.
    public init(engine: any ParseExecuting = ParseEngine(),
                options: MarkdownParseOptions = .default,
                debounce: Duration = .milliseconds(150))

    /// Debounced: cancels any pending parse and schedules a new one after
    /// `debounce`. Coalesces rapid keystrokes into ≤ 2 parses (acceptance).
    public func textDidChange(_ text: String)

    /// Immediate parse, bypassing the debounce (document open, tests).
    /// Cancels any pending debounced parse first. Publishes AND returns.
    @discardableResult
    public func parseNow(_ text: String) async -> MarkdownDocument?

    /// Cancels any pending/running parse without publishing.
    public func cancelPending()

    /// Reparse the last text with new options (E13 will call this; tests now).
    public func setOptions(_ options: MarkdownParseOptions)
}

/// identity (tab UUID string) → session. Mirrors EditorTextSystemStore.
@MainActor
public final class MarkdownParseStore {
    public init(engine: any ParseExecuting = ParseEngine())
    public func session(for identity: String) -> MarkdownParseSession
    public func existingSession(for identity: String) -> MarkdownParseSession?
    public func evict(_ identity: String)
    public func evictAll()
}
```

**Session semantics (exact, testable):**
1. `textDidChange` stores the text, cancels the in-flight debounce `Task`, starts a new one: `try await Task.sleep(for: debounce)` → call `engine.parse` with `revision = nextRevision()` → publish.
2. Publishing guard: `guard result.revision > (document?.revision ?? Int.min)` — stale results are dropped silently (D5).
3. `CancellationError` (from sleep or engine) is swallowed — it is the *normal* coalescing path. Any other engine error is also non-fatal: log via `os_log`, keep the previous `document`. The engine as specified cannot throw anything else, but the session must not crash if a future conformer does.
4. `isParsing` is true from `textDidChange` until publish/cancellation settles; flapping during coalescing is acceptable (no UI consumes it yet).
5. Revisions are session-scoped, monotonic, starting at 1.

### 4.4 Front-matter extraction contract (exact)

Input is the full original source. Rules, in order:

1. Strip a single leading U+FEFF (BOM) for detection only (offsets in `SourceMap` still count it — it is part of the UTF-16 content).
2. Front matter exists iff **line 1** matches `^---[ \t]*$` **and** some later line matches `^(---|\.\.\.)[ \t]*$`. First such later line is the closing delimiter.
3. No closing delimiter ⇒ **no front matter** (the whole text is Markdown body; a lone `---` opener is a thematic break, per CommonMark, and that is correct behaviour).
4. `raw` = the lines strictly between the delimiters, joined with `\n`, exactly as written (no trimming).
5. `values` = Yams-parsed `raw` **iff** it parses to a mapping with String keys; every YAML scalar/sequence/mapping converts to `FrontMatterValue` (ints parse as `.number`; `y/n/yes/no` follow whatever Yams' core schema says — do not hand-roll bool coercion). Malformed YAML or non-mapping root ⇒ `values = nil` (still front matter — D3).
6. `body` = everything after the closing-delimiter line (empty string if nothing follows). `bodyLineOffset` = closing delimiter's line number.
7. The extractor is a pure `internal static func` on its own type (`FrontMatterExtractor`) so it unit-tests in isolation.

### 4.5 Block conversion & source-index contract (exact)

Inside the actor, after swift-markdown parses `body`:

1. Walk the `Markdown.Document` children recursively, mapping each `BlockMarkup` to `MarkdownBlock` per the `BlockKind` table (§4.2). Inline markup is skipped except `Heading.plainText` → `HeadingItem.title`.
2. Line numbers: swift-markdown gives per-node `SourceRange` in **body** coordinates → add `bodyLineOffset` to every line before storing (D4). A node with a missing/invalid range (defensive; should not happen with `Document(parsing:)`) inherits its parent's range, and the top-level fallback is `1...1` — never crash, never produce an empty range.
3. `codeBlock(language:)`: fenced blocks take the info string's first whitespace-separated token, lowercased; empty ⇒ nil. Indented code blocks ⇒ nil.
4. `table(columnCount:)` from `Table.maxColumnCount` (or head-row cell count — whichever the API provides; record which on the PR).
5. `listItem(taskState:)` from swift-markdown's checkbox property (`.checked`/`.unchecked`/nil).
6. Unknown `BlockMarkup` conformers ⇒ `.custom(String(describing: type(of: node)))`, children still converted (ground rule 5).
7. `headings` = in-order flatten of every `.heading` block. Headings inside blockquotes/lists ARE included (they carry real anchor value); headings inside code fences are never Markdown headings in the first place, so the "code-block headings ignored" E08 acceptance is satisfied by the parser itself — write the test anyway (§7).
8. `SourceMap` is built from the ORIGINAL text in one pass (count UTF-16 units, record each offset after `\n`). Empty text ⇒ `lineCount == 1`, `lineStartOffsets == [0]`.

### 4.6 Threading / concurrency model

- `ParseEngine`: `actor`, runs on the global executor (never main — enforced by `dispatchPrecondition` in `parse`).
- `MarkdownParseSession` / `MarkdownParseStore`: `@MainActor` (they touch UI-adjacent state and are created/torn down with windows).
- Every public type is `Sendable`; the compiler proves it (no `@unchecked`). swift-markdown/Yams types are confined inside the actor and never escape (D1/D3).
- No locks, no queues, no Combine anywhere.

### 4.7 Failure matrix (graceful totality)

| Failure | Behaviour |
|---|---|
| Malformed YAML in front matter | `FrontMatter.values == nil`; body still parses; no error surfaced (D3) |
| Unknown block node type | `.custom(name)`, children preserved (§4.5.6) |
| Node without a source range | Inherits parent range; top-level fallback `1...1` (§4.5.2) |
| Parse cancelled (coalescing) | `CancellationError` swallowed by the session; previous `document` stands (§4.3.3) |
| Pathological input (deep nesting, emphasis bombs) | No special-casing — cmark-gfm handles these; the §7 pathological perf test documents the cost and catches regressions |
| Engine throws unexpectedly (future conformer) | Session logs, keeps previous `document`, never crashes (§4.3.3) |

### 4.8 App-target integration

**None in this epic.** The app continues to render the placeholder preview from raw text. E07 creates the `MarkdownParseStore` per window (next to `editorStore`/`highlightStore` in `WindowController`), calls `textDidChange` from the editor binding, and consumes `session.document`. This is deliberate: it keeps this PR package-only, single-pass, and CI-complete. (The store/session API above was shaped against `WindowController`'s existing per-window pattern so E07's wiring is mechanical.)

---

## 5. File layout (exact)

```
MacDown2/Packages/MacDownKit/Sources/MarkdownEngine/
  MarkdownParseOptions.swift
  FrontMatter.swift              (FrontMatter, FrontMatterValue, FrontMatterExtractor)
  MarkdownBlock.swift            (BlockKind, TaskState, MarkdownBlock, HeadingItem)
  SourceMap.swift
  MarkdownDocument.swift
  ParseEngine.swift              (actor; the ONLY file importing Markdown + Yams)
  ParseExecuting.swift
  MarkdownParseSession.swift
  MarkdownParseStore.swift
  LegacyPlaceholderRenderer.swift  (moved renderAttributed + helpers, verbatim; D6)

MacDown2/Packages/MacDownKit/Tests/MarkdownEngineTests/
  Fixtures.swift                 (inline builders: GFM corpus, front-matter variants,
                                  1 MB / 10 MB generators, pathological inputs)
  FrontMatterTests.swift
  BlockConversionTests.swift
  HeadingTests.swift
  SourceMapTests.swift
  OptionsTests.swift
  SessionDebounceTests.swift     (spy ParseExecuting + real-engine coalescing test)
  ParseEnginePerformanceTests.swift
```

`MarkdownEngineTests.swift` (the stub test) is deleted, as `HighlightingTests.swift`/`ThemesTests.swift` were in E05. The old `MarkdownEngine.swift` placeholder file is deleted; its content moves to `LegacyPlaceholderRenderer.swift` unchanged (D6) so `Preview` keeps compiling with **zero `Preview` diffs**.

---

## 6. Build-config changes (exact)

`MacDown2/Packages/MacDownKit/Package.swift`:

```swift
// dependencies: — ADD (pin the latest tag at implementation time; record resolved
// versions on the PR. MIGRATION_PLAN §5 says swift-markdown 0.8.x; use `exact:`
// with the tag you resolve, per the pinning policy):
.package(url: "https://github.com/swiftlang/swift-markdown", exact: "<resolved>"),
.package(url: "https://github.com/jpsim/Yams", exact: "<resolved>"),

// targets: — CHANGE MarkdownEngine (FileCore dependency REMOVED — the engine
// uses no FileCore type; purity is the contract):
.target(name: "MarkdownEngine", dependencies: [
    .product(name: "Markdown", package: "swift-markdown"),
    .product(name: "Yams", package: "Yams"),
]),
// — and CHANGE Preview, which today gets FileCore transitively via MarkdownEngine:
.target(name: "Preview", dependencies: ["MarkdownEngine", "Themes", "FileCore"]),
```

No `project.yml` change (no app-target change, no new resources). No `ci.yml` change (`swift test` already runs the whole suite). If `swift build` surfaces another target that was leaning on the transitive `FileCore`, add the explicit dependency the same way — do not restore it on `MarkdownEngine`.

---

## 7. Test plan (mapped to issue #7 acceptance)

| # | Issue acceptance box | Test (all `swift test`, CI) |
|---|---|---|
| 1 | 20 rapid keystrokes ⇒ ≤ 2 parses | `SessionDebounceTests`: session with `debounce: .milliseconds(50)` + real engine; fire `textDidChange` 20× at ~5 ms intervals; settle; `#expect(completedParseCount <= 2)`. Plus a spy-engine test asserting stale-revision results are not published |
| 2 | Tables/task lists/strikethrough/footnotes per GFM | `BlockConversionTests` over the GFM corpus fixture: exact `BlockKind` tree asserted for tables (column count), ordered/unordered lists, task states, nested quotes, fenced code (language token), thematic breaks, HTML blocks. Strikethrough/autolinks are inline ⇒ asserted indirectly (paragraph parses, no crash) with a comment saying so. Footnotes: asserted if supported, else the test documents the D7 finding with a skipped-reason |
| 3 | Front matter absent from AST body | `FrontMatterTests`: valid mapping / malformed YAML / non-mapping root / missing closer / `...` closer / empty block / BOM-prefixed — each asserts `frontMatter`, `bodyLineOffset`, and that `blocks` contains no artefact of the block (no `thematicBreak` at line 1, headings at correct original lines) |
| 4 | Source-range index correct on the corpus | `SourceMapTests` + `BlockConversionTests`: every top-level block's `lineRange` matches hand-computed values on the corpus (with and without front matter); `utf16Range(ofLines:)`/`line(atUTF16Offset:)` round-trip incl. CRLF, emoji (surrogate pairs), empty text, and last-line-no-newline |
| 5 | Parse off main thread, strict-concurrency clean | The `dispatchPrecondition` in `ParseEngine.parse` makes every test a main-thread assertion; plus one explicit test calling `parseNow` from `@MainActor` and asserting a result arrives (proves the hop) |
| — | Perf: 1 MB re-parse < 150 ms (release target) | `ParseEnginePerformanceTests.parse1MB`: `ContinuousClock` around `engine.parse` on the 1 MB generator; assert the **2 s debug documentation ceiling** (E05 precedent), log the measured duration; the 150 ms budget is verified locally in release and recorded on the PR (§10.4) |
| — | 10 MB representative (#28 area 2 groundwork) | `parse10MB`: 10 s documentation ceiling, duration logged — establishes the package-level baseline the #28 full-path measurements will subtract from |
| — | Pathological inputs | `parsePathological`: deep blockquote nesting (1k) + long emphasis-delimiter run; generous ceiling; regression tripwire for cmark quadratic edges |
| — | Options | `OptionsTests`: `setOptions` triggers a reparse (spy engine sees new options + new revision); `.default` equals all-true |

House rules carried from E05: Swift Testing `@Test`/`#expect` only; no `Task.sleep`-and-hope in debounce tests — await deterministic signals (poll `completedParseCount` with a bounded timeout helper in `Fixtures.swift`); no real `UserDefaults`; no fixture files on disk (inline builders).

## 8. Implementation order (suite green at every step)

1. `MarkdownParseOptions` + `FrontMatterValue`/`FrontMatter` + `FrontMatterExtractor` → `FrontMatterTests`.
2. `SourceMap` → `SourceMapTests`.
3. `BlockKind`/`MarkdownBlock`/`HeadingItem`/`MarkdownDocument` (no parser yet — pure types).
4. Package.swift deltas (§6); resolve + record pins.
5. `ParseEngine` conversion walk → `BlockConversionTests`, `HeadingTests`.
6. `ParseExecuting` + `MarkdownParseSession` → `SessionDebounceTests`.
7. `MarkdownParseStore` (trivial; mirror `EditorTextSystemStore` tests if any — else covered by session tests).
8. Move placeholder → `LegacyPlaceholderRenderer.swift`; delete old stub files; verify `Preview` builds with zero diffs.
9. `ParseEnginePerformanceTests`; run release-build local timing; record numbers.

## 9. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test        # gates 1–8
cd ../.. && xcodegen generate                                        # unchanged, but CI runs it
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
# Locally, release timing for the PR record:
swift test -c release --filter ParseEnginePerformanceTests
```

## 10. Open decisions (flag on the PR — do not silently resolve)

1. **swift-markdown resolved version** (MIGRATION_PLAN says 0.8.x, July 2026) and **which GFM extensions are individually toggleable** through its `ParseOptions`. Record the mapping table in the PR description (D7).
2. **Footnote support**: if swift-markdown 0.8.x does not parse footnotes, `footnoteDefinition` stays unproduced, the `footnotes` option is documented always-ignored, and E12 (which uses swift-cmark directly) inherits the decision. Flag either way.
3. **Yams resolved version** + confirmation that its core-schema bool/number coercion matches §4.4.5 expectations (write the tests against observed behaviour and document it).
4. **Measured perf numbers** (debug CI + release local, 1 MB/10 MB/pathological) vs the 150 ms budget — record with headroom, per E05 §10.2 precedent.
5. **`Table` column-count API** — `maxColumnCount` vs head-count (§4.5.4); record which.

## 11. Hand-off notes / known pitfalls (condensed — mirrored to the PR inline comment)

- **swift-markdown and Yams types never leave `ParseEngine.swift`** (D1/D3). If you find yourself writing `import Markdown` in a second file, stop.
- **All public line numbers are ORIGINAL-source 1-based lines** — add `bodyLineOffset` when converting from body coordinates, and never expose columns (D4).
- **Front matter is delimiter-defined, not validity-defined** (D3). Malformed YAML is still front matter with `values == nil`.
- **Conversion is total**: unknown node ⇒ `.custom`, missing range ⇒ inherit parent — never crash, never drop (§4.5, §4.7).
- **Debounce is cancel-and-restart on the main actor; the actor only parses** (D5). The revision guard is mandatory even though cancellation makes staleness rare.
- **No app-target changes, no Preview changes** — the placeholder renderer moves file-verbatim (D6) and E07 owns all wiring (§4.8).
- **`dispatchPrecondition(.notOnQueue(.main))` in `parse`** is the off-main acceptance test; do not remove it to make a test pass.
- **Pin `exact:` versions** for both new deps and list resolved versions in the PR (§6, §10).
- **Perf gates use E05's convention**: debug documentation ceilings in CI, real budgets measured locally in release and recorded on the PR.
