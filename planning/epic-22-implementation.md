# EPIC-22 implementation architecture: Editor essentials (power-text workflows before macOS 1.0)

> Baseline: `master` at commit `95e4f6005f7f0a998b6c03377a17d92b8c1fcef7` (2026-09-21), immediately after EPIC-16's interim localisation baseline (PR #111) and the owner's "Plan final pre-release debt closure and E23" / "Complete carried-forward debt audit" planning commits. Epic issue: [#112](https://github.com/Joncallim/macdown_2/issues/112).

## 1. Owner summary

**What changes for the user?** MacDown 2 currently opens, edits, previews, exports and searches (via the stock macOS Find bar) Markdown and a dozen other text formats, but it is missing the everyday power-text-editor primitives that make CotEditor, BBEdit, Sublime Text and VS Code reach-for tools: multiple cursors, a line-number gutter, a real status bar, Cmd-P fuzzy file navigation, project-wide search/replace, and small but disproportionately useful commands like Duplicate Line, Sort Lines and Toggle Comment. After this epic, choosing MacDown 2 over those apps for ordinary text work should not mean giving up a basic editing habit.

**Why now?** The macOS 1.0 roadmap under-specified these workflows; the app is excellent at Markdown/technical writing but was never audited against "is this a good *general* text editor." The owner approved this epic explicitly, after E16's localisation work had already started, as a bounded, final pre-release capability addition — sequenced before the final public-identity re-freeze, before E23 (themes/Quick Look/Finder polish), and before EPIC-17 (distribution/release).

**Main technical approach.** EditorCore is *not* replaced. Its existing per-window `EditorTextSystem`/TextKit 2/one-`NSTextViewDelegate` architecture is extended: a new plural selection model (`EditorSelectionSet`) sits alongside the existing singular `selectedRange`, a new line-index type (`EditorLineIndex`) feeds the gutter/status bar/Go to Line, and a new `LanguageEditingProfile` generalises E10's pairing/indentation engine (currently Markdown-only) to every registered text format. A new `TextSearch` SwiftPM package owns search/index/fuzzy-scoring as pure, UI-free, actor-isolated types shared by current-document find and workspace-wide folder search. All new file mutation (encoding conversion, line-ending conversion, replace-in-folder) is built exclusively on `FileStore`'s existing expected-revision/conditional-publication guarantee — no new ad hoc write path is introduced anywhere.

**Main risks/compromises.** (1) Multi-cursor editing has no existing precedent in this codebase — every current selection/undo/publication path assumes exactly one range, so this is genuinely new architecture, not an extension of one. (2) TextKit 2 invisibles rendering and a line-number gutter must not force the legacy `NSLayoutManager` or defeat the proven viewport-lazy layout (a 10 MB document currently lays out under 500 fragments — `EditorPerformanceTests.open10MBLazy`). (3) `.tex`/`.latex` source recognition and highlighting have zero existing scaffolding — this is a from-scratch `FileFormatRegistry`/`GrammarRegistry` addition, and no tree-sitter LaTeX grammar is currently vendored, so the architecture gate below makes an explicit, evidence-based choice rather than assuming one is available. (4) E05's cited performance budgets (50 ms keystroke / 500 ms full-highlight / 8 ms main-thread) have never actually been enforced — the existing tests assert an 8-*second* ceiling in Debug and call the Release numbers "verified locally" with no corroborating artifact anywhere in the repository. This epic must establish real Release evidence, not repeat the unverified claim.

**What is deliberately not being built:** LSP/semantic completion, an integrated terminal, source control UI, a debugger, a plugin marketplace, code folding, a minimap, split-editor-on-one-document, full TextMate snippet grammar, and a full symmetric-editor peer to CotEditor/BBEdit's most exotic tools. See the epic issue's "Explicitly out of scope" section for the complete list; it is unchanged by this document.

## 2. Baseline and repository reconciliation

### 2.1 What already exists and must be reused, not duplicated

Confirmed by direct source inspection at the baseline SHA above (file:line citations throughout this document are current as of that commit):

- **TextKit 2, no legacy layout manager.** `TextKitStack` (`EditorCore/TextKitStack.swift`) assembles `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer` + `NSTextView` directly; `usesLegacyTextKit1` is a documented no-op stub. No file in `EditorCore` or the app target ever references `NSLayoutManager`. Viewport-laziness is not a custom `NSTextViewportLayoutControllerDelegate` — it is `NSTextLayoutManager`'s own default fragment-materialization behaviour, and `EditorCore` deliberately never asks it to lay out beyond the visible region (`EditorTextSystem.syncFrameHeightToContent()`'s doc comment is explicit about this; `layoutFragmentFrame(atUTF16Location:)` and `ensureLayout(for:)` in `EditorTextSystem+Scroll.swift` both request layout for one explicit range/fragment only, never the whole document). `EditorPerformanceTests.open10MBLazy` pins this: a 10 MB document must lay out under 500 fragments.
- **Singular selection, everywhere.** `EditorTextSystem.selectedRange: NSRange` (`EditorTextSystem+Scroll.swift`) is the *only* selection accessor. There is no `selectedRanges` anywhere in `EditorCore`, the app target, or tests. Session persistence (`WorkspaceSession.TabRecord.cursorPosition: Int?` / `.selectionLength: Int?`) stores one scalar pair, not an array. The full preview/outline-follows-caret pipeline (`EditorView.Coordinator.textViewDidChangeSelection` → `onSelectionChange: (NSRange) -> Void` → `OutlineController.referenceOffsetDidChange(Int)`) is single-range at every hop.
- **Three independent hand-rolled "one edit, one undo group" patterns**, no shared primitive: `applyDocumentReplacement(_:undoActionName:)`, `applyExternalReplacement(_:in:undoActionName:)`, and `applyAssistOutcome(_:)` (all in `EditorTextSystem+*.swift`) each independently wrap one `insertText(_:replacementRange:)` call in `textView.breakUndoCoalescing()` / `setActionName(...)` / a provenance flag (`isPerformingEditingAssist` or none). There is no `beginUndoGrouping()`/`endUndoGrouping()` call anywhere in the codebase. Ordinary keystrokes rely entirely on native `NSTextView` undo coalescing.
- **`showsInvisibles` is genuinely, completely unconsumed.** `EditorConfiguration.showsInvisibles` is plumbed correctly from `EditorSettingsPane`'s real, working `Toggle("Show invisible characters", ...)` through `AppSettings.EditorSettings` and `DocumentEditorSplitView.editorConfiguration` all the way to `EditorTextSystem.apply(_:)` — and `apply(_:)` never reads it. Every other `EditorConfiguration` field has a corresponding statement in `apply(_:)`; `showsInvisibles` has none. `EditorChrome.invisibles: ThemeColor?` (the color that would presumably paint them) is equally unconsumed — `NeonSyntaxHighlighter.applyChrome(theme:)` applies `background`/`foreground`/`caret`/`selection` only.
- **`EditorChrome.currentLine: ThemeColor?`** (`Themes/TokenStyle.swift`) is declared, decodable, and initializable, but has no consumer anywhere in the codebase and no value in either bundled theme JSON. This is the exact "handed forward from E05 to E10, never shipped" field the epic issue names.
- **E10's pairing/indentation engine is Markdown-only by explicit app-boundary gate**, not by accident: `DocumentEditorSplitView.editorConfiguration` sets `config.editingAssists = document.format.id == "markdown" ? assistConfiguration(...) : .disabled`. The underlying engine (`MarkdownEditingAssistEngine`, called out by name) already implements a data-driven "structural pair table" (`(`/`)`, `[`/`]`, curly/guillemet/CJK quote pairs) that is *not* inherently Markdown-specific — only the Markdown-symmetric-delimiter handling (`*`, `_`, backtick) and list/blockquote/task continuation are genuinely Markdown-only. `EditorSettings.indentationWidth`/`.convertsTabsToSpaces` are single global values, translated once into `EditingAssistConfiguration`, and — per the same Markdown-only gate — never reach a non-Markdown document's indentation behaviour today. No `LanguageEditingProfile`-shaped type, comment-delimiter table, or paired-delimiter-per-format table exists anywhere (confirmed by repo-wide grep).
- **E10 is deliberately not AST-aware**, and says so in its own architecture doc (`epic-10-implementation.md` §2.6): "E10 does not consult the debounced Markdown AST... assists are enabled throughout a Markdown file... a conscious limitation." Its non-negotiable rule #7 ("No full Markdown parse on the hot path") and rule #9 ("No additional whole-document extraction on the common path... read local ranges from live text storage") are the binding precedent for how E22's fenced-code/front-matter classifier (§9 below) must be built: synchronous, local, bounded — never the debounced `MarkdownEngine` AST.
- **`FileStore`'s conditional-publication guarantee is real and battle-tested**, and is exactly what replace-in-folder must reuse per file: `FileStore.write(_:to:encoding:bom:expectedRevision:)` — when given `expectedRevision` — verifies the on-disk revision twice, then performs an atomic `renameatx_np(..., RENAME_SWAP)` exchange, re-verifies the displaced (previously-on-disk) bytes against the expected baseline, and on any mismatch either rolls back (if it can prove nothing else raced in during rollback) or preserves the external writer's bytes at a sibling `.name.external-recovery-<uuid>` path and throws `.conditionalPublicationRecoveryRequired(URL)` — it never silently discards either side. `WorkspaceModel+Saving.reconcileSaveConflict` already demonstrates the intended reuse pattern (retry once on a metadata-only mismatch, surface a real conflict otherwise).
- **Strict, no-fallback encoding detection with zero legacy-encoding support.** `FileStore+Encoding.decode(_:)` detects UTF-8 BOM → UTF-16 LE/BE BOM → strict UTF-8, and nothing else; there is no code path today for Windows-1252, Latin-1, Shift-JIS, MacRoman, etc. `FileEncodingMetadata`'s `Decodable` initializer additionally collapses *any* encoding outside `{utf8, utf16, utf16LE, utf16BE}` to `.utf8Default` on session restore — this is the exact "every non-UTF encoding is corrupt" validation the epic issue says must be broadened. `FileDocument.saveAs(_:encodingOverride:)` already has a working `encodingOverride: FileEncodingMetadata?` parameter with the right precedence (`encodingOverride ?? encoding`) — the write-side seam for "Save With Encoding…" already exists; only the read side and the plain-`save()` override, plus the UI command, do not.
- **No line-ending infrastructure exists at all** (no `LineEnding` type, no CRLF/LF/CR detection, no conversion). The current "no silent normalisation" guarantee is an emergent property of `FileStore` never touching line-ending bytes, pinned by `TextRoundTripFidelityTests` (CRLF, mixed, and bare-CR round-trip tests). This is from-scratch work that must not regress those tests.
- **Security-scoped folder access already works and should be reused as-is.** The app carries no sandbox entitlements, but `FolderAccessScope` (RAII start/stop) + `RecentFolderRoots` (bookmark persistence, physical-identity dedup, staleness refresh) already give every open folder root a live, re-launch-safe access grant, held for the lifetime of that window's `FileTreeModel`. `WorkspaceFileIndex` must consume `FileTreeModel.root`/`.rootAccessURL` rather than inventing a second bookmark store.
- **No recursive whole-tree traversal exists anywhere** — `FileTree`'s `DirectoryReading`/`FileSystemDirectoryReader` is single-level, lazy, expand-on-click only; the sidebar never walks more than the currently-expanded set. `WorkspaceFileIndex`'s recursive walk is genuinely new code; it does **not** literally call `DirectoryReading.contents(of:)` (§5.1 fixes `TextSearch` to depend only on `FileCore`, never `FileTree`, so a direct call is not available across that boundary) but its own local `DirectoryWalker` must still classify hidden/package/symlink entries *consistently* with it, and must add its own symlink-loop guard (nothing today prevents infinite recursion in a *recursive* walk — `FileTreeCopySafety`'s ancestor check solves a different problem, move/copy destination validation, not traversal). **This consistency point was missed on first implementation and caught by an external automated review of the Slice 1 pull request:** the first `DirectoryWalker` queried `.isDirectoryKey` on each child's own (unresolved) URL, but resource values describe the *link itself* on some file systems, so a symlink to a directory could report `isDirectory == false` and be silently indexed as a file with its entire subtree dropped — silently defeating both Quick Open coverage and the symlink-loop guard's own test (which, before the fix, never actually recursed through the test's symlink at all, so it "passed" without exercising the loop-guard path it claimed to). Fixed by mirroring `FileSystemDirectoryReader.contents(of:)`'s existing resolve-and-recheck: for a symlink, additionally resolve and query the *target's* resource values and OR the two `isDirectory` results together.
- **`Task.detached` + generation/reload-token staleness guards are the established async pattern** (`FileTreeModel.generation`, `reloadTokens`) and the 250 ms debounced watcher-driven rescan (`FileTreeModel+TreeState.watchEvent`) is the established reaction-to-external-change pattern. `WorkspaceFileIndex` must use the same shape for its own build/rebuild.
- **Cmd-D is currently bound to Folder "Duplicate"**, gated only by `coordinator.keyFolderSelection != nil` (`WindowCoordinator+FileTree.keyFolderSelection`) — a check that is **not** first-responder-aware: it looks only at whether the sidebar has a selected row for the key window, so today, selecting a sidebar row and then clicking into the editor to type leaves Cmd-D still routed to Duplicate. The existing, correct precedent for the responder-aware disambiguation E22 needs is `WindowCoordinator+Editing.canPerformMarkdownEditingCommand`/`performMarkdownEditingCommand`, which checks `NSApp.keyWindow?.firstResponder === textSystem.textView` at *both* menu-enablement time and invocation time (menu enablement is "convenience, not a safety boundary," per its own doc comment), and `commandStateRevision` — a manually-bumped counter read by `Commands` menu validation to force SwiftUI to re-evaluate `.disabled(...)` after AppKit focus changes that SwiftUI cannot observe on its own (`DocumentWindow.sendEvent`, `WindowCoordinator.commandStateDidChange()`).
- **⌘P is completely free.** Exhaustive grep confirms no existing binding uses plain Cmd-P; the Command Palette is Shift-Cmd-P (`TextFilterCommands.swift`) and is unaffected.
- **The command palette is a genuinely separate, hand-maintained list**, `AppPaletteCommand.standard` (`MacDown2/AppPaletteCommand.swift`, 9 entries), explicitly documented in its own doc comment as "a small, explicit, hand-maintained array — not generated from `WorkspaceCommands`... per that section's accepted drift-risk tradeoff at this list's current size." `WorkspaceCommands.swift` declares roughly 30 real menu commands (SwiftUI `Commands`-builder syntax, not an enumerable/reflectable array — the two categories of real functionality most conspicuously missing from the palette today are the whole Folder submenu, tab-switching, Layout/Theme, and every Markdown-formatting command). The only existing palette test that touches completeness is `CommandPaletteModelTests.standardCommandsContainNoExportRow` — a single, deliberate negative assertion for one excluded command, not a general check. No test anywhere references `WorkspaceCommands` at all. This is exactly issue #117 item 4's "eliminate command-palette registry drift," which E22 owns, and E14's own architecture doc (`epic-14-implementation.md` §18 residual risk 5) pre-committed to exactly this follow-up once the list grew enough to justify it. A ready-made structural template already exists in this codebase for the "strong consistency test with explicit exclusions" the issue permits as an alternative to a single canonical source: `HighlightingTests/FormatRegistryConsistencyTests.swift` validates two independently-maintained sources (`FileFormatRegistry` vs. `FormatManifest`) against each other via a `*Consistency.validate(...) -> Report` object with a structured `issues` list, plus drift-injection tests proving the validator actually detects a mismatch. §5.3 below adopts this exact shape for commands.
- **`MarkdownParseOptions`'s five inert fields** are `tables`, `taskLists`, `strikethrough`, `autolinks`, `footnotes`; only `blockDirectives` is wired to a real swift-markdown 0.8.0 parse flag (`ParseEngine.swift`'s only branch on `options.*`). Direct inspection of the vendored swift-markdown/cmark-gfm sources (`.build/checkouts/swift-markdown`, `swift-cmark`) shows the five are **not uniformly "always on"** the way the app's own settings-pane footer copy implies:
  - `tables`, `taskLists`, `strikethrough` genuinely are unconditionally active — `CommonMarkConverter.parseString` attaches the `table`/`tasklist`/`strikethrough` cmark-gfm syntax extensions to every parse with no conditional.
  - `autolinks` is not "on" so much as *silently degraded*: swift-markdown never attaches cmark-gfm's `autolink` extension at all, so only base-CommonMark bracketed autolinks (`<https://…>`) work — a `false` value would produce identical behaviour to `true` today, but so would any other value, because the GFM extended-autolink feature the field's name implies is entirely absent.
  - `footnotes` has **zero engine support** — there is no footnote markup-node type anywhere in swift-markdown and no footnote cmark-gfm extension in the vendored source at all; `[^1]`-style syntax renders as literal text regardless of this field's value.
  - `MarkdownSettings` (the settings-layer type, `AppSettings/MarkdownSettings.swift`) already contains **only** `parsesBlockDirectives` — E13 independently reached the same "five fields are inert" conclusion and deliberately did not expose them as toggles, so **the settings UI (`MarkdownSettingsPane`) has no misleading control to fix today**; its one `Toggle` is the real, wired option, and its footer text already discloses the always-on behaviour (imprecisely, per the distinction above, but not as a live toggle bound to nothing). The residual debt is entirely at the `MarkdownEngine.MarkdownParseOptions` **public struct shape** — a 6-field API with 5 fields whose `init` silently accepts `false` with no effect, a trap for any future caller (export code, a future settings redesign, a plugin) who does not read the doc comment.
  - The correct 1.0 disposition (per issue #53's own text, "Revisit if/when swift-markdown… adds that control," and confirmed by the vendored-source inspection that no such control exists) is to remove or recast these five fields from the public API shape rather than invent parser plumbing that does not exist upstream — and any recast copy should reflect the `autolinks`/`footnotes` distinction above rather than repeat the codebase's current blanket "always parse" phrasing.
- **`FileFormatRegistry.defaultFormats`** currently has 16 entries (markdown, html, json, yaml, toml, javascript, typescript, python, ruby, css, swift, c/cpp, bash, sql, xml, plaintext). `.tex`/`.latex` has *zero* existing registration anywhere — not in the format registry, not in `FormatManifest` (the OS document-type contract), not in `project.yml`. The existing "LaTeX" code in the repository (`Math`/`MathRendering` packages) parses inline `$...$`/`$$...$$` math spans embedded in Markdown — an unrelated subsystem. No tree-sitter LaTeX grammar is vendored or available as a currently-integrated SPM dependency; `GrammarRegistry`'s 16 registered language ids (`GrammarRegistry+Factories.swift`) do not include one.
- **E05's cited performance budgets are unenforced.** `HighlightPerformanceTests`' three tests all assert `< .seconds(8)` — a 1000x-160x looser ceiling than the doc comment's claimed Release numbers (50 ms/500 ms/8 ms), and CI only ever runs `swift test` (Debug configuration; no `-c release` flag anywhere in `ci.yml`'s package-test step). The claim that Release numbers are "verified locally and recorded on the epic PRs" has no corroborating file anywhere in `planning/`. The 1 MB fixture itself is genuine (confirmed real ~1 MB Markdown text), so only the assertion/configuration is deficient, not the test's premise.

### 2.2 Stale assumptions reconciled

- The epic issue's Scope §1 implies invisibles rendering is a "finish the wiring" job. It is closer to "add the wiring from nothing": `EditorConfiguration.showsInvisibles` and `EditorChrome.invisibles` are both fully inert, and TextKit 2 has no built-in `showsInvisibleCharacters`-equivalent flag (that API belongs to legacy `NSLayoutManager`) — invisibles must be a custom rendering layer (see §9.1).
- The issue's `EditorChrome.currentLine` reference implies a value exists somewhere close to shippable; in fact zero themes populate it and zero code consumes it. E22's current-line work is a genuine two-sided implementation (consumer *and* real theme values), not a wiring fix.
- Issue #53's "wire a real parser capability where one exists" framing (as read in isolation) could imply some of the five inert fields are wireable. Direct inspection shows none of the five have any swift-markdown-side lever to pull; the correct disposition is field removal/recasting as unconditional, not conditional wiring — confirmed by the issue's own text, not overridden by this document.
- `MacDown 2`, the identity used throughout this document, code comments and default UI strings, is the **development identity only** — the owner has already decided to ship under a new name (`MIGRATION_PLAN.md` §11, 2026-09-21). Per the owner's explicit instruction accompanying this epic, E22 must not freeze that new identity and should keep new implementation identity-neutral where practical (e.g., avoid baking "MacDown 2"-specific strings into new non-localised code paths beyond what's already established, and do not create new bundle-identifier-adjacent surface area). Existing `String(localized:)` UI copy that says "MacDown 2" is out of scope to rename here; the re-freeze epoch (between E22 and E23) is where that happens.

### 2.3 Dependencies and follow-ups this epic intersects

- **E05** (`epic-05-implementation.md`, closed): inherits real performance-evidence debt (§2.1 above) — binding on E22 per the 2026-09-21 closed-epic audit.
- **E10** (`epic-10-implementation.md`, closed): inherits the fenced-code/front-matter Markdown-assist gating limitation, explicitly deferred to "a focused follow-up" by its own architecture doc; E22 is that follow-up.
- **E11** (`epic-11-implementation.md`, closed): inherits `.tex`/`.latex` source recognition, explicitly left unimplemented.
- **E13** (`epic-13-implementation.md`, closed) / issue **#53**: E22 owns only the `MarkdownParseOptions` parser-model half; the legacy MacDown preference *import* half of #53 remains E17's.
- **E14** (`epic-14-implementation.md`, closed) / issue **#117**: E22 owns only item 4 (command-palette registry drift); items 1/2/3/5 (HTML contribution contract, TOC navigability, extra export parse, `ExportCoordinator` targeting) belong to E23/#118/#115 and are out of scope here.
- **Issue #79** (Mermaid/D2/Graphviz theme coherence) and **#88** (XCUITest execution gaps): not owned by E22. E22 must keep the UI journeys #88 already exercises green as it changes selection/editing/menu code, but does not attempt to close #88 itself (per the owner's explicit instruction: "do not claim the final #88/manual evidence gate until the near-final product exists").
- **Issue #118** (Export security/parity/evidence) and **#121** (HTML Preview resource-read races): not this epic's scope, but E22's block-directive/`MarkdownParseOptions` disposition (§2.1) is a stated input #118 needs later — E22 must leave that decision unambiguous, not defer it further.

## 3. User journeys

**J1 — Edit a config file like a power user.** Open a `.yaml` file. See logical line numbers in a gutter and a status bar showing line/column, encoding, and line-ending state. Press Cmd-D on a repeated key name to select the next occurrence, repeat to select all three occurrences, type a replacement once, and see all three update with one undo step. Toggle-comment a block with Cmd-/.

**J2 — Multi-cursor Markdown edit that respects fences.** In a Markdown document, put the caret inside a fenced ` ```json ` block containing a JSON array. Press Return after a line ending in `,` — no Markdown list continuation is injected (the fence classifier suppresses it), and pressing Tab inside the fence indents using the *general* language profile, not Markdown's list-indent behaviour. Move the caret back into ordinary prose and Markdown assists resume immediately.

**J3 — Regex find/replace across one document, recover from a bad pattern.** Open Find (existing shortcut), switch to regex mode, type an invalid pattern — see an inline diagnostic, not a silent zero-result state. Fix the pattern, see a live match count, use "Select All Matches" to convert every match into a multi-selection, and edit all of them at once.

**J4 — Quick Open a file across a large project without freezing.** With a 50k-file folder open, press Cmd-P, type a fuzzy fragment of a nested file's name, and see it near the top of a capped, ranked result list within the performance budget, without the keystroke triggering a new disk traversal.

**J5 — Safe multi-file replace.** Run a folder-wide regex search, review a preview of affected files/counts, confirm, and have the replacement apply file-by-file; a file that changed externally between search and replace is skipped and reported, never silently overwritten, and its original encoding/BOM/line-ending convention is preserved.

**J6 — Recover from an encoding mistake.** Open a file MacDown 2 auto-detected as UTF-8 that is actually Windows-1252 and shows visibly wrong characters. Use "Reopen Using Encoding…", pick Windows-1252, and see the correct text with no data loss; if the reopen fails to decode losslessly, the currently-open (wrong-looking but intact) document is left completely untouched.

**J7 — A snippet with multi-cursor.** With three cursors active (via occurrence selection), invoke "Insert Snippet…" for a snippet containing `${selection}` and `$0`; the snippet expands independently at each cursor, respecting each one's own indentation and leaving the final caret at each `$0`.

**J8 — TeX source, no accidental Markdown treatment.** Open a `.tex` file. It is recognised as TeX/LaTeX, gets syntax highlighting (or a documented, tested fallback if the architecture gate in §9.6 concludes no safe highlighter dependency is available), receives general-format editing mechanics (comment/indent/pairing) via `LanguageEditingProfile`, and is never handed to the Markdown parser or preview.

## 4. Non-negotiable invariants

Carried forward from the repository's existing invariants (`RELEASE_HARDENING.md`, `MIGRATION_PLAN.md`) plus epic-specific ones:

1. **One `NSTextViewDelegate.`** `EditorView.Coordinator` remains the sole delegate; E22 does not introduce an `NSTextView` subclass with its own `keyDown` override.
2. **TextKit 2 only.** No code path may access the legacy `NSLayoutManager`, and no invisibles/gutter/current-line rendering may force TextKit 1 compatibility mode.
3. **Viewport-lazy layout is preserved.** A gutter, gutter gutter-caret-highlight, or invisibles overlay may only draw for fragments actually materialized in the current viewport pass; none may call an API that forces whole-document layout. `EditorPerformanceTests.open10MBLazy`'s <500-fragment assertion must keep passing unmodified in spirit (a new test may be added for gutter-specific laziness; the existing one must not be weakened).
4. **All editor offsets are UTF-16.** `NSRange`, UTF-16-aware line/range helpers. Never `String.count` for editor positions — the existing rule from E10, unchanged and now generalised to every new E22 type (`EditorLineIndex`, `EditorSelectionSet`, `TextSearchEngine`).
5. **No silent file normalisation.** Encoding, BOM, and line endings are preserved exactly unless a user takes an explicit, named, undoable action (Reopen/Save With Encoding, an explicit EOL conversion command). A plain open→save round trip remains byte-identical for anything `TextRoundTripFidelityTests` already covers.
6. **File writes only through `FileStore`'s conditional-publication path.** No new ad hoc `String`/`Data` write, no shell tool, for any of: Save With Encoding, EOL conversion, or replace-in-folder. Every write that could race an external change carries an `expectedRevision` and handles `.conditionalPublicationRecoveryRequired`/`.fileChangedDuringRead` the same way `WorkspaceModel+Saving` already does.
7. **Dirty local text is never silently discarded** by any new command — this includes a failed "Reopen Using Encoding…" (the current document must be left completely untouched on failure) and any multi-cursor edit that partially fails.
8. **Untitled/recovery identity model is unchanged.** No new write path introduces a second identity scheme alongside `FileDocument`'s `(id, recoveryEpoch)`; nothing in E22 changes when `recoveryEpoch` rotates.
9. **IME composition fails open.** Exactly like E10's existing `hasMarkedText()`/`markedRange()` guard, no E22 custom text-manipulation logic (multi-cursor fan-out, snippet expansion, general-format pairing) may run while there is active marked text or the affected range intersects it.
10. **One user command remains one undo group and one document publication**, now generalised: a multi-cursor edit affecting N ranges is one undo step, not N.
11. **Unsupported/misidentified formats fail closed.** A `.tex`/`.latex` file with no available highlighter falls back to plain-text rendering with correct format identity — never silent Markdown treatment, never a crash.
12. **No hidden fallback changes the security model.** Folder search/replace reuses existing `FolderAccessScope`/`FileStore` guarantees; it does not read/write outside the already-granted root without the same access pattern the sidebar already uses.

## 5. Ownership and dependency boundaries

### 5.1 New package: `TextSearch`

A new SwiftPM target in `MacDownKit`, depending only on `FileCore` + Foundation (mirroring the existing package-dependency discipline — see `Package.swift`'s existing target list, none of which currently exist for this purpose). Owns, with **no AppKit, SwiftUI, or window/tab knowledge**:

- `SearchQuery`, `SearchOptions`, `SearchMatch` — pure value types.
- `TextSearchEngine` — single-buffer literal/regex search over a `String`/`NSString`, cancellable, off-main.
- `WorkspaceFileIndex` — an actor building/holding an in-memory snapshot of `(relativePath, basename)` pairs under a root, with fuzzy-scoring support.
- `WorkspaceSearchEngine` — folder-wide search orchestration (streaming results, filters, caps) over paths the index already knows about, reading file bytes through `FileCore` primitives.
- Replace-planning/result types (`ReplacementPlan`, per-file preview/outcome types) — data only; the actual `FileStore` write call is made by the app-target orchestrator (§5.1 continues below), not by `TextSearch` itself, since `TextSearch` must not depend on `Workspace`'s document-model layer.
- Fuzzy path-scoring utility, shared verbatim by Quick Open and (per issue #117) the command palette's own fuzzy filtering, so the two do not silently diverge in ranking behaviour.

`EditorCore` may import `TextSearch` for the pure single-buffer types it needs for current-document find (`SearchQuery`/`SearchOptions`/`SearchMatch`/`TextSearchEngine`), but `TextSearch` must never import `EditorCore` (search is lower-level, shared infrastructure — the same one-directional-dependency discipline `Contributions`/`MarkdownEngine` already follow elsewhere in the package graph).

### 5.2 `EditorCore` evolves in place

New types/files live in `EditorCore` alongside the existing `EditorTextSystem`/`EditorConfiguration`/`EditingAssistConfiguration` — this is an extension of the existing package, not a new one:

- `EditorLineIndex` (§8) — logical-line UTF-16 offset index, incrementally maintained.
- `EditorSelectionSet` (§7) — ordered, non-overlapping, primary-selection-aware multi-range model.
- `EditorEditTransaction` / a disjoint multi-replacement primitive (§7.3) — the generalized "one command, one undo group, one publication" seam the codebase currently lacks.
- `LanguageEditingProfile` (§9) — per-format comment/pairing/indentation data, consumed by a generalized (renamed or extended) editing-assist engine.
- Gutter/status/invisibles presentation types (thin, `EditorView`-adjacent; actual SwiftUI/AppKit drawing may live in the app target the same way `EditorView` itself does today, or in `EditorCore` if it needs direct `NSTextLayoutManager` access — decided per-slice, not pre-committed here, since neither §2.1's evidence nor the current `EditorView`/`EditorCore` split forces one answer; the slice 2 implementation must record its choice and reasoning in this document's changelog).

`EditorCore` continues to own no window/tab/session concept; those remain the app target's (`WindowCoordinator`, `DocumentEditorSplitView`) and `Workspace`'s (`TabStore`) responsibility.

### 5.3 App target coordinates cross-cutting concerns

- Folder search UI, Quick Open panel, Replace-in-Folder preview/confirmation UI, and the actual `FileStore` writes for replace-in-folder (composing `TextSearch`'s planning types with `Workspace`/`FileCore`'s document-safety primitives) live in the app target, mirroring how `WorkspaceModel+Saving`/`DocumentWriter` already orchestrate `FileStore` today.
- Command routing/first-responder disambiguation (Cmd-D) lives in `WindowCoordinator`/`DocumentWindow`, extending the existing `canPerformMarkdownEditingCommand`/`commandStateRevision` pattern rather than inventing a new one.
- **The command-palette consistency mechanism** touches `WorkspaceCommands.swift` and `AppPaletteCommand.swift`, both already app-target files. Since SwiftUI `Commands` cannot be enumerated/reflected at runtime (§2.1), the design is a **canonical, explicit descriptor list** — not a change to how `WorkspaceCommands` builds its menu, but a new, small, hand-written `EligibleCommandCatalog: [CommandDescriptor]` (id + title + `paletteEligible: Bool` + an exclusion reason string when `false`) that names every real `WorkspaceCommands` entry once. A new `CommandRegistryConsistency.validate(catalog:paletteCommands:) -> Report`, structurally mirroring `FormatRegistryConsistencyTests`' existing `*Consistency.validate(...) -> Report`/`issues` shape (§2.1), asserts every catalog entry marked `paletteEligible` has a matching `AppPaletteCommand.standard` id, and every `AppPaletteCommand.standard` id appears in the catalog — plus a drift-injection test (adding a fake catalog entry with no palette counterpart, and vice versa) proving the validator actually fails when it should, matching `FormatRegistryConsistencyTests.validationDetectsCapabilityModeDrift`'s existing precedent. This is deliberately the "consistency test with explicit exclusions" option the issue permits, not a `WorkspaceCommands` rewrite — lower risk to ~30 already-working shortcuts than making the menu itself data-driven.

### 5.4 `FileCore` gains encoding/EOL surface, not a new I/O path

- `FileEncodingMetadata` validation is broadened (§11.1) to accept the legacy encodings E22 exposes, without changing its role as a `Codable` session-record guard.
- A new `LineEndingProfile`/`LineEnding` type (§11.3) is added to `FileCore` (it is a text-fidelity concept, same layer as `FileEncodingMetadata`/`FileBOM`), consumed by the app-target EOL-conversion command, never by `FileStore.write` implicitly.
- `FileStore` itself gains **no new write variant** — encoding/EOL conversion and replace-in-folder all call the existing `write(_:to:encoding:bom:expectedRevision:)`.

### 5.5 `Highlighting`/`FileCore` for `.tex`/`.latex`

A new `FileFormat` entry (`FileCore`), a new `FormatManifest` declaration, a new `project.yml` UTI, and — pending the architecture gate's evidence-based decision (§9.6) — either a new `GrammarRegistry` factory entry or a documented, tested "no highlighter, plain-text-styled but format-correct" fallback. `LanguageEditingProfile` gets a TeX entry regardless of the highlighting decision (comment mechanics do not require tree-sitter).

## 6. Types and interfaces

This section specifies binding contracts for the slice-1/2 foundational types (implemented first, per §12) in enough detail that a worker cannot invent the ownership/threading model; later-slice types (search UI wiring, snippet store, encoding commands) are specified to the same rigor once their slice begins, per `EPIC_STANDARD.md`'s "the implementation architecture is divided into dependency-ordered slices" model — §6.1-6.3 below are binding now, §6.4 onward define the contract each later slice must satisfy without pre-inventing UI-layer detail that belongs to that slice's own worked example.

### 6.1 `EditorLineIndex` (EditorCore)

```swift
/// Maintains UTF-16 logical line-start offsets for one document's live text.
/// Powers the gutter, status bar, Go to Line/Column, and logical-line
/// commands (Duplicate/Move/Sort/Join/Trim). A "logical line" is a source
/// line as delimited by LF/CRLF/CR — never a wrapped visual line.
public struct EditorLineIndex: Sendable, Equatable {
    /// UTF-16 offset at which each 1-based logical line starts.
    /// `lineStartOffsets[0]` is always 0 (line 1).
    public private(set) var lineStartOffsets: [Int]
    public private(set) var utf16Length: Int

    public init(text: NSString)

    /// Incremental update from one edit: the UTF-16 range that was replaced
    /// in the *previous* text, and the replacement's UTF-16 length. Must not
    /// rescan text outside `[affectedRange.lowerBound, end of edit]` plus a
    /// bounded lookback to the start of the affected line.
    public mutating func applying(editedRange: NSRange, replacementUTF16Length: Int, newText: NSString)

    /// Full rebuild — only for whole-document replacement/reload, matching
    /// `applyDocumentReplacement`'s existing "whole document changed" case.
    public mutating func rebuild(text: NSString)

    public var lineCount: Int { get }
    public func line(atUTF16Offset offset: Int) -&gt; Int
    public func utf16Range(ofLine line: Int, in text: NSString) -&gt; NSRange
    /// Character (not UTF-16 unit) column for user-facing display —
    /// `SourceMap`'s existing line-mapping precedent uses UTF-16 internally
    /// and characters for display; `EditorLineIndex` must do the same so
    /// Go to Line/Column's user-facing numbers match CJK/emoji expectations.
    public func column(atUTF16Offset offset: Int, onLine line: Int) -&gt; Int
}
```

**Why a new type instead of reusing `SourceMap` or `NeonSyntaxHighlighter`'s private line-offset table (§2.1):** both existing implementations are full-document O(n) rescans on every rebuild, one is Markdown-parse-debounced (lags live text), the other is private to the highlighter and rebuilds on every content revision (i.e. every keystroke) with no incremental-update path. A gutter needs a *live*, *incremental*, *format-neutral* index that never lags the text the user is looking at and never re-scans the whole document per keystroke on a large file. This is new infrastructure, not a duplication risk — but its line/column semantics (UTF-16 internal, character-count-for-display) must match `SourceMap`'s existing convention exactly, since Go to Line/Column and search-result line numbers must agree with the outline/preview's existing line numbering for the same document.

**Threading:** plain `Sendable` value type, mutated only from the main actor inside `EditorTextSystem`'s existing edit-application call sites (the same actor context every current mutation already runs in). No actor of its own — it is cheap enough (per the performance budget in §11) to update synchronously on every edit.

**A real bug found by an external automated review of the Slice 1 pull request, confirmed by hand-tracing and fixed:** the first implementation's "one line of margin" was one-sided — trailing only. `applying(editedRange:replacementUTF16Length:newText:)` computed `rescanStart` as the start of the line *containing* the edit, so when the edit's location fell exactly at that line's start and the *preceding* line ended in a lone (non-CRLF) `\r`, the rescan never re-examined that untouched `\r` at all, and so could never notice it newly pairing with an inserted leading `\n` into a real CRLF. Concretely: a one-character document `"\r"` (a single bare-CR-terminated empty line) with `"\n"` appended produced incremental offsets `[0, 1, 2]` (three lines) instead of the correct, full-rebuild-matching `[0, 2]` (two lines) — a phantom line that would have misreported gutter and Go to Line/Column positions. Fixed by mirroring the existing trailing margin with a symmetric **leading** margin: the rescan window now always starts one full line earlier than the edit's own line (when a preceding line exists), which provably always includes that line's terminating character without needing to special-case which terminator style is at risk. Regression test: `EditorLineIndexTests.incrementalNewlineAfterTrailingBareCRFormsCRLF`.

### 6.2 `EditorSelectionSet` (EditorCore)

```swift
/// Ordered, non-overlapping UTF-16 selection ranges with one designated
/// primary. Bridges to/from `NSTextView.selectedRanges`.
public struct EditorSelectionSet: Sendable, Equatable {
    /// Always non-empty; always sorted ascending by location; always
    /// pairwise non-overlapping (touching/adjacent ranges are permitted and
    /// distinct — normalization only merges genuinely overlapping ranges).
    public private(set) var ranges: [NSRange]
    /// Index into `ranges` of the primary selection (the one Preview/outline
    /// tracking follows, and the one a plain Escape collapses to).
    public private(set) var primaryIndex: Int

    public init(single range: NSRange)
    public init(ranges: [NSRange], primaryIndex: Int) // normalizes + validates

    public var primaryRange: NSRange { ranges[primaryIndex] }
    public var isMultiple: Bool { ranges.count &gt; 1 }

    public mutating func addRange(_ range: NSRange, makePrimary: Bool)
    public mutating func removeRange(at index: Int)
    /// Collapses to just the primary range (Escape).
    public mutating func collapseToPrimary()
    /// Clamps every range against `newLength` after an edit elsewhere
    /// invalidates offsets (mirrors `EditorViewportSnapshot`'s existing
    /// single-range clamp-on-reload precedent).
    public mutating func clamped(toLength newLength: Int) -&gt; EditorSelectionSet

    /// AppKit bridge.
    public init?(selectedRanges: [NSValue]) // nil if empty/malformed input
    public var asNSValueArray: [NSValue] { get }
}
```

**Session-restore impact (explicit, not deferred):** `WorkspaceSession.TabRecord` persists only `cursorPosition`/`selectionLength` (the primary range) — per the epic issue's explicit "Session restore may persist only the primary selection for 1.0. Multi-cursor state is disposable editing UI state," this document records that `TabRecord`'s schema does **not** change; `EditorSelectionSet`'s non-primary ranges are simply not captured by `TabStore+Session`'s existing snapshot code. No new session schema version is introduced by this type.

**Threading:** plain value type, same main-actor mutation context as today's `selectedRange`.

**A second real bug found by the same external review, confirmed and fixed:** `indexClosest(to:in:)` (the private helper that re-finds a caller's intended primary range after normalization may have merged/reordered ranges) used an *inclusive* containment check (`location <= target.location && target.location <= location + length`). For two distinct, merely-**touching** ranges (which `normalize` deliberately does not merge — e.g. `[0,5)` and `[5,6)`), that inclusive check let the earlier range `[0,5)` wrongly claim the boundary point 5, which actually belongs only to `[5,6)`. Concretely, constructing a set with primary `[5,6)` and sibling `[0,5)` silently resolved the primary to `[0,5)` instead — a real, silent primary-selection misassignment. Fixed by making containment half-open for nonempty ranges (`location <= target.location && target.location < location + length`, consistent with every other range comparison this type makes) with zero-length candidates matched by exact location equality instead (a point range has no interior to contain anything with). Regression test: `EditorSelectionSetTests.primaryAtTouchingBoundaryStaysWithItsOwnRange`.

### 6.3 `EditorEditTransaction` (EditorCore)

```swift
/// One disjoint multi-range text replacement applied as exactly one native
/// edit sequence, one undo group, one document-change publication —
/// generalizing the three existing hand-rolled one-edit patterns
/// (`applyDocumentReplacement`, `applyExternalReplacement`,
/// `applyAssistOutcome`) to N simultaneous, non-overlapping ranges.
public struct TextReplacement: Sendable, Equatable {
    public let range: NSRange   // in the *pre-edit* text
    public let replacementText: String
}

public struct EditorEditTransaction: Sendable {
    /// Must be in-bounds and non-overlapping; validated ATOMICALLY, as one
    /// set, in `apply(_:)` (not at construction, so a transaction can be
    /// freely built and inspected before it is ever applied), via a pure,
    /// directly unit-testable helper: fatal in Debug (an
    /// `assertionFailure`, visible during development), rejects the ENTIRE
    /// transaction in Release — no partial application of even the
    /// individually-valid members — mutating no text, selection, or undo
    /// state and publishing nothing, rather than corrupting text or
    /// executing part of a malformed command. A transaction is one atomic
    /// user command; "fail closed" here means the whole command fails
    /// together, mirroring the existing discipline this codebase already
    /// uses for other malformed input (e.g. `FileStore`'s decode
    /// failures).
    public let replacements: [TextReplacement]
    public let undoActionName: String?
    /// The `EditorSelectionSet` to install after applying, expressed in
    /// *post-edit* offsets (the caller computes this; the transaction does
    /// not guess caret placement).
    public let resultingSelection: EditorSelectionSet?
}

extension EditorTextSystem {
    /// Applies every replacement highest-offset-to-lowest (so earlier
    /// offsets are never invalidated by a later replacement), inside one
    /// `breakUndoCoalescing()`/`setActionName`/`breakUndoCoalescing()`
    /// bracket — i.e. exactly the existing three call sites' shape,
    /// generalized to N ranges instead of 1. Marks
    /// `isPerformingEditingAssist` for the duration (existing flag, existing
    /// meaning: "dirties the document as a real user edit, but the
    /// assist/multi-cursor engine does not reinterpret its own output").
    public func apply(_ transaction: EditorEditTransaction)
}
```

This is the primitive every new multi-cursor typing/paste/delete/indent/transform command, and every existing single-range command that chooses to adopt it, funnels through. It does not replace `applyDocumentReplacement`/`applyExternalReplacement` (whole-document and text-filter output remain their own simpler cases) — it is the new general case for N &gt; 1 disjoint ranges, including N == 1 (a single-cursor command may use it too, and should, in preference to hand-rolling a fourth ad hoc pattern).

**A real problem found and fixed while implementing this in Slice 1, not anticipated when this contract was first drafted:** the existing single-replacement patterns never had to worry about "one publication," because a single `textView.insertText(_:replacementRange:)` call naturally posts AppKit's text-change notification exactly once. For N &gt; 1 calls in a loop, each one independently posts that notification, and `EditorView.Coordinator.textDidChange` — which reads `system.text` and forwards it to the SwiftUI binding — has no existing guard against this, so a 3-range transaction published the binding 3 times with intermediate, not-yet-fully-edited text, not once with the final result. Fixed by adding a new guard, `EditorTextSystem.isApplyingMultiRangeTransaction` (mirroring `isPerformingProgrammaticTextUpdate`'s existing shape), which `EditorEditTransaction`'s `apply(_:)` raises before the loop and lowers immediately before the *last* `insertText` call, so `textDidChange` suppresses every intermediate notification and only the final one — which by then reflects every replacement — reaches the binding. Verified with a real mounted `NSTextView`/binding-publication-counter integration test (`EditorEditTransactionTests.multiRangeIsOneUndoStepAndOnePublication`), not inferred from reading the code.

**A second correction, made after an external automated review of the Slice 1 pull request correctly challenged the first draft of this contract:** the original implementation used `precondition` to reject overlapping replacements, and this document originally (incorrectly) described that as "Debug-fatal, Release-drops" — but Swift's `precondition` traps in both Debug **and** standard optimized Release builds (only `-Ounchecked`, which this codebase does not build with, compiles it out), so the described Release fallback was unreachable dead code, contradicted by no test (nothing exercised the overlap path at all). Fixed properly, not merely re-documented: the bounds/overlap check was extracted into a pure function that performs no build-configuration-dependent trap of its own and is directly unit-tested against genuinely malformed input; `apply(_:)` switched from `precondition` to `assertionFailure`, which traps in Debug but is a true no-op in Release. The same preflight also now rejects an out-of-bounds replacement (location/end outside the current document length), which the original implementation never checked at all — also flagged by the same review.

**A third correction, made explicitly by the epic owner reviewing the second correction's own design:** that second fix still applied the longest *valid prefix* of an otherwise-malformed transaction (dropping only the entries from the first invalid one onward) rather than rejecting the transaction outright — an inconsistency with this section's own framing of a transaction as ONE atomic user command. Corrected to true all-or-nothing semantics: `EditorEditTransaction.validate(_:documentLength:)` returns a single `Bool` for the whole set (not a partial "applied" list), and `apply(_:)` mutates nothing at all — no text change, no selection change, no undo entry, no publication — when any single member is invalid, even if every other member would individually have succeeded. `validate` was also rewritten to use `zip(sorted, sorted.dropFirst())` for the pairwise-disjointness check instead of `1 ..< sorted.count` index arithmetic, closing a real crash the prefix-based version's own test suite exposed: `validate([], documentLength:)` — a legitimately valid, expected input (an empty transaction) — triggered `1 ..< 0`, a fatal `Range requires lowerBound <= upperBound`. A second flaky (not incorrect) test was found and fixed in the same pass: a supersession test asserted a *specific* winner between two `async let`-raced actor calls, which Swift's concurrency model gives no ordering guarantee over; rewritten to assert the property `WorkspaceFileIndex`'s generation counter actually, deterministically guarantees — exactly one root's contents survive, never a corrupted mix.

### 6.4 `LanguageEditingProfile` (EditorCore) — contract, detailed implementation in Slice 4

```swift
/// Editor mechanics for one text format, keyed from `FileFormat.id`/
/// `highlightLanguageID`. Contains only mechanics — no semantic/LSP
/// behavior.
public struct LanguageEditingProfile: Sendable, Equatable {
    public var lineComment: String?
    public var blockComment: (open: String, close: String)?
    public var pairedDelimiters: [PairedDelimiter]  // reuses E10's existing structural-pair shape
    public var indentAfterTrailing: Set&lt;Character&gt;  // e.g. "{" for C-family
    public var defaultIndentWidth: Int?  // format-specific override; nil defers to the global EditorSettings value

    public static let plainText = LanguageEditingProfile() // all-nil/empty: passthrough to native behavior
}
```

Consumed by generalizing the existing (currently Markdown-only-gated) pairing/Tab-indent engine to run for *every* format via its profile, while the Markdown-*symmetric-delimiter* and list/blockquote continuation logic remains behind the existing `document.format.id == "markdown"` gate (per §9's fenced-code disposition, that gate itself gains fence/front-matter awareness — it is not removed). Slice 4 is where the exact refactor of `MarkdownEditingAssistEngine` into a format-neutral core plus a Markdown-specific layer is designed in full and recorded as an addendum to this document.

### 6.5 `TextSearchEngine` (TextSearch package) — contract, detailed implementation in Slice 5

```swift
public struct SearchOptions: Sendable, Equatable {
    public var isRegex: Bool
    public var isCaseSensitive: Bool
    public var isWholeWord: Bool
    public var wraps: Bool
    public var searchesSelectionOnly: Bool
}

public enum SearchQueryError: Error, Equatable {
    case invalidRegex(String) // localized diagnostic message, never a silent empty result
}

public struct SearchMatch: Sendable, Equatable {
    public let range: NSRange // UTF-16, in the searched buffer
}

public struct TextSearchEngine: Sendable {
    /// Pure, synchronous, single-buffer search — used directly by
    /// current-document find on a bounded buffer, and per-file by
    /// `WorkspaceSearchEngine` (folder search) inside its own cancellable
    /// off-main task.
    public static func matches(
        in text: String,
        query: String,
        options: SearchOptions
    ) throws(SearchQueryError) -&gt; [SearchMatch]
}
```

Cancellation/off-main-actor policy, `WorkspaceFileIndex`'s exact actor shape, and the fuzzy-scoring algorithm are specified in full when Slice 5/6 begins, per the same "detailed contract fixed at the point the slice starts" convention `EPIC_STANDARD.md` §1 (Layer 3) describes — committing to an exact fuzzy-ranking formula now, before the foundational line-index/selection work has landed and been reviewed, would risk exactly the "invent architecture the worker wasn't asked to invent" failure mode the standard warns against. What *is* fixed now: `TextSearch` owns these types, they are pure Foundation, and folder search must reuse the identical `TextSearchEngine.matches` call per file rather than a second regex/literal implementation.

### 6.6 `EditorLineIndex` wiring + line-number gutter (Slice 2a) — baseline and contract

**Baseline, verified against live master before writing this contract (no prior code exists for any of this):**
- `EditorTextSystem` has no edit chokepoint: `applyDocumentReplacement`/`applyExternalReplacement`/`applyAssistOutcome` (one each) and `EditorEditTransaction.apply(_:)` (N ranges, Slice 1) all call `textView.insertText(_:replacementRange:)`; raw typing goes through AppKit's own internal handling. `setText(_:)`/`replaceTextFromExternal(...)` set `textView.string` directly (bypassing the delegate entirely) and manually bump `editRevision` — confirmed these do NOT trigger `NSTextViewDelegate` callbacks.
- `EditorView.Coordinator` already implements `textView(_:shouldChangeTextIn:replacementString:)` (fires before every edit, any origin, with the affected range in pre-edit coordinates and the exact replacement string — including for each individual `insertText` call inside an `EditorEditTransaction`'s loop) and `textDidChange(_:)` (fires after; currently suppressed for every call but the last in a multi-range transaction, via `isApplyingMultiRangeTransaction`, purely to avoid re-publishing the SwiftUI binding N times — see §6.3).
- `EditorChrome.invisibles: ThemeColor?` (`Sources/Themes/TokenStyle.swift`) and `EditorConfiguration.showsInvisibles` are both fully declared but genuinely inert: neither is read by `NeonSyntaxHighlighter.applyChrome(theme:)` nor by `EditorTextSystem.apply(_:)`. No gutter, status bar, or Go to Line UI exists in any form (stub or otherwise) anywhere in the package or app target.
- `EditorTextSystem+Scroll.swift` already exposes `topVisibleUTF16Offset` (resolves the layout fragment at the clip view's origin) and `layoutFragmentFrame(atUTF16Location:)` (forces layout for one explicit, bounded range only, via `enumerateTextLayoutFragments(from:options: [.ensuresLayout])`) — these are the only existing viewport-bounded layout queries, and a gutter must use the same bounded-range discipline, never enumerate the whole document's fragments.
- `EditorPerformanceTests.open10MBLazy` pins `<500` materialized fragments for a 10 MB document at a fixed viewport size, by counting `layoutManager.enumerateTextLayoutFragments(from:options: .ensuresLayout)` results bounded to the viewport height. A gutter that iterates `EditorLineIndex.lineStartOffsets` for the *whole document* to place `lineCount` label views would not violate this exact assertion (the assertion only measures `NSTextLayoutManager` fragments) but would violate its *spirit* and this epic's own performance discipline — it must draw line numbers only for lines whose fragments are already materialized in the current viewport, discovered by walking `layoutManager.enumerateTextLayoutFragments(from:options:)` starting at `topVisibleUTF16Offset`, exactly mirroring the existing viewport-query pattern.
- Nearest UI-chrome precedent for a floating panel (relevant to Slice 2b's Go to Line, noted here for continuity): `CommandPalettePanel`/`WindowCoordinator+CommandPalette.swift` — an `NSPanel` with `[.titled, .fullSizeContentView, .closable]`, hidden title, floating level, hosting a SwiftUI view via `NSHostingView`, held strongly by `WindowCoordinator` since `NSPanel.isReleasedWhenClosed == false`.

**Wiring contract:**

```swift
// EditorTextSystem.swift
public final class EditorTextSystem {
    /// Kept current with every edit this text system observes, incrementally
    /// (never a full rescan except on whole-document replacement). Powers
    /// the gutter, status bar, and Go to Line/Column.
    public private(set) var lineIndex: EditorLineIndex

    /// Called once per atomic edit — including once per individual range
    /// inside an `EditorEditTransaction`, independent of that transaction's
    /// own SwiftUI-publication suppression, since the line index must stay
    /// correct for every intermediate state, not just the transaction's
    /// final one. `editedRange` is in *pre-edit* coordinates; `newText` is
    /// read directly from the already-mutated live text view (an O(1)
    /// reference, not a copy) — this must never be synthesized via
    /// `NSString.replacingCharacters(in:with:)` before the edit happens,
    /// which would cost an O(document length) copy per keystroke and defeat
    /// the incremental index's entire purpose.
    func noteIncrementalEdit(editedRange: NSRange, replacementUTF16Length: Int)
}
```

`setText(_:)` and `replaceTextFromExternal(...)` call `lineIndex.rebuild(text:)` (full rebuild — these are the type's own documented "whole document changed" case, and both already bypass the incremental delegate path entirely). `EditorTextSystem.init` builds the initial index from `initialText`.

**`EditorView.Coordinator` wiring:** a new private `pendingLineIndexEdit: (range: NSRange, replacementUTF16Length: Int)?` is set at the top of `shouldChangeTextIn` (before every existing branch, including the E10/marked-text early returns, so it captures literally every edit this delegate observes) and consumed at the top of `textDidChange` (before the existing `isApplyingMultiRangeTransaction` publication-suppression guard, so the index updates for every one of an N-range transaction's individual edits even though only the last one publishes to SwiftUI). This relies on `shouldChangeTextIn`/`textDidChange` firing in strict alternation per edit, including for E10's own nested internal edit when it intercepts and replaces an outer one (verified by tracing `EditorTextSystem+EditingAssists.swift`'s `applyAssistOutcome` call chain): the nested edit's own `shouldChangeTextIn` overwrites `pendingLineIndexEdit` before the nested `textDidChange` consumes it, and the outer (vetoed) edit that follows never fires its own `textDidChange` at all, so nothing is left stale. Proven with real, AppKit-driven (not synthetic) integration tests comparing `system.lineIndex` against a fresh `EditorLineIndex(text:)` rebuild after each of: plain typing, an E10-intercepted edit, a multi-range `EditorEditTransaction`, and undo/redo.

**Gutter contract:** a new `EditorGutterView: NSRulerView` (or equivalent `NSView` subclass docked to the scroll view's ruler area) queries `system.lineIndex.line(atUTF16Offset:)`/`.column(atUTF16Offset:onLine:in:)` and the viewport-bounded fragment enumeration described above to draw only the currently-materialized visible lines' numbers — never the whole document. Detailed view-layer API (exact class shape, redraw triggering) is fixed in the Slice 2a worked implementation itself, per `EPIC_STANDARD.md`'s Layer 3 convention, since it is UI-layer detail this document's Layer 2 contract does not need to pre-invent.

### 6.7 Go to Line/Column + status bar (Slice 2b) — baseline and contract

**Baseline, verified against live master (`a2b52c9`) before writing this contract:** no status bar, Go to Line/Column command, or inverse line/column lookup exists anywhere in the package or app target (grepped both trees for `StatusBar`, `GoToLine`, `jumpToLine`, `"Ln "`, `"Col "` — the only hits are this document's own and `EditorLineIndex`/`EditorTextSystem`'s doc-comment mentions of these as *future* consumers). `EditorLineIndex` has forward lookup (`line(atUTF16Offset:)`, `column(atUTF16Offset:onLine:in:)`) but no inverse (line, column) → UTF-16 offset lookup. `EditorTextSystem+Scroll.swift`'s `revealSelection(utf16Range:flash:animated:)` already exists and is already used by the outline sidebar's jump feature (`DocumentEditorSplitView.swift`) — Go to Line/Column is a straightforward third caller, not a new mechanism. The nearest floating-panel precedent is `CommandPalettePanel` (§6.6 above). `EditorView`'s `editorPane` composition (`DocumentEditorSplitView.swift`) hosts `EditorView` directly with no surrounding container; a status bar needs a new `VStack` wrapper there.

**Scope correction against the epic issue's literal status-bar item list:** issue #112 lists, "at minimum": primary line/column; selection count when multiple selections exist; selected/document character or word count; indentation mode/width; active syntax/highlight mode (opens syntax selection); line-ending state LF/CRLF/CR/Mixed (opens conversion actions); encoding (opens encoding actions). Four of these have real, undelivered dependencies on LATER slices per §17's own dependency order: multi-selection count needs `EditorSelectionSet` wired as `EditorTextSystem`'s actual selection source of truth (Slice 3, not yet done — `EditorTextSystem` is still single-`selectedRange`); line-ending state and its conversion actions need `LineEndingProfile` (Slice 8, does not exist yet); encoding actions need Slice 8's broadened encoding UI; syntax-mode selection needs Slice 9's per-document syntax override. Implementing placeholder versions of any of these now would mean re-doing them when their owning slice lands — exactly the risk `EPIC_STANDARD.md`'s Layer 2/3 split exists to avoid. Slice 2b therefore ships the three items with no forward dependency — **line/column, selected/document character and word count, indentation mode/width** — as real, working, actionable-where-specified status items, and the status bar's own item model is an ordered, extensible list (`[StatusBarItem]` or equivalent) specifically so Slices 3/8/9 each *append* their item later rather than needing to touch this slice's layout code again. This is recorded here, not silently: the epic issue's status-bar checkbox is not fully closed by Slice 2b alone.

**Also split out of this slice for the same reason `EPIC_STANDARD.md`/§17 already split Slice 2 into 2a/2b:** TextKit-2-safe invisibles rendering is real, novel, character-glyph-level AppKit drawing (no existing precedent anywhere in this codebase — the gutter only draws once per *line*, at a line's start; invisibles must draw once per *character* within a line, using `NSTextLineFragment`'s per-character glyph-origin API) whose actual visual fidelity this session cannot verify by screenshot the way `EditorGutterViewTests` already discloses it cannot for the gutter either — it can only be geometry-tested, not eyeballed. Bundling it with the status bar and Go to Line (both low-risk, precedent-following UI/data work) would repeat the "monolithic change" failure mode. It becomes **Slice 2c**, sequenced immediately after 2b, once 2b is merged and proven — see the renumbered §17 below.

**Go to Line/Column contract:**
```swift
// EditorLineIndex.swift — the missing inverse lookup
public extension EditorLineIndex {
    /// UTF-16 offset for a 1-based (line, column) pair. `column` is a
    /// 1-based character (grapheme-cluster) count, matching
    /// `column(atUTF16Offset:onLine:in:)`'s existing convention. Out-of-range
    /// `line` clamps to `1...lineCount`; out-of-range `column` clamps to the
    /// target line's actual length (never past its terminator).
    func utf16Offset(forLine line: Int, column: Int, in text: NSString) -> Int
}
```
A new app-target `GoToLinePanel` (an `NSPanel`, matching `CommandPalettePanel`'s exact idiom: `[.titled, .fullSizeContentView, .closable]`, hidden title, floating level, `NSHostingView`-hosted SwiftUI content, held strongly by `WindowCoordinator` since `NSPanel.isReleasedWhenClosed == false`) accepts a `"line[:column]"` text field, parses it (invalid/out-of-range input clamps rather than errors, per `EditorLineIndex`'s own established clamping convention throughout), computes the target UTF-16 offset via the new inverse lookup, and calls the existing `system.revealSelection(utf16Range:flash: true, animated: true)` — no new scroll/selection mechanism. Bound to Ctrl-G per the issue's stated preference (confirmed against the live keyboard-shortcut audit before final assignment, in case of a conflict this document has not yet surfaced).

**Status bar contract:** a new SwiftUI `EditorStatusBarView` (app target, since its content — word count, indentation settings — is app/session-owned state that `EditorCore` does not otherwise need to know about, per §5.2's "decided per-slice" ownership split; only `EditorLineIndex`/`selectedRange`, both already public, cross the `EditorCore` boundary) is composed as `VStack(spacing: 0) { EditorView(...); EditorStatusBarView(...) }` inside `editorPane`, with the existing `.frame(width:)` modifier moved from `EditorView` onto the new `VStack`. Content:
- **Line/column:** `EditorLineIndex.line(atUTF16Offset:)`/`.column(atUTF16Offset:onLine:in:)` at `selectedRange.location`; clicking opens `GoToLinePanel`.
- **Character/word count:** selected range's character count when non-empty, else the whole document's; word count via `String.enumerateSubstrings(in:options: [.byWords])` (no new tokenizer — reuses Foundation's existing word-boundary logic, consistent with this codebase's "reuse Foundation before inventing" pattern elsewhere).
- **Indentation mode/width:** read from `EditingAssistConfiguration.indentationWidth`/`convertsTabsToSpaces` (already-existing settings, `AppSettings/EditorSettings.swift`); not yet actionable (no indentation-options popover exists to open — adding one is not this item's job and is not blocked on any later slice, so it may land as a small, separate, non-epic-blocking follow-up whenever the owner wants it, not invented here to avoid speculative UI).
- A durable `showsStatusBar` setting is added to `EditorSettings` alongside the existing `showsInvisibles`, per issue #112 §F ("Add durable settings only: show line numbers, show status bar, show invisibles..." — `showsInvisibles`'s own settings toggle already exists from before this epic; `showsStatusBar` does not).

**Tests:** `EditorLineIndex.utf16Offset(forLine:column:)` — round-trips against `line(atUTF16Offset:)`/`column(atUTF16Offset:onLine:in:)` for LF/CRLF/CR/mixed/Unicode/CJK/emoji fixtures, plus explicit out-of-range clamping cases (line 0, line beyond `lineCount`, column 0, column beyond line length); a real-`NSPanel`-mounted `GoToLinePanel` integration test parallel to `EditorViewRealMountTests`' mounting discipline; status bar word/character count against known fixtures (empty document, single word, CJK/emoji character counting, an active selection vs. none).

## 7. State and data flow

### 7.1 Selection: editor → outline/preview (extends existing single-range flow)

```
NSTextView (native, multi-range via selectedRanges)
  → EditorView.Coordinator.textViewDidChangeSelection
    → EditorTextSystem.selectionSet: EditorSelectionSet  (NEW — replaces raw selectedRange as the source of truth)
      → EditorTextSystem.selectedRange (COMPUTED, = selectionSet.primaryRange, kept for source compatibility with any code not yet selection-set-aware)
      → EditorView.onSelectionChange(selectionSet.primaryRange)  (UNCHANGED signature and call sites: OutlineController continues to follow only the primary selection, per the epic's explicit "Preview/outline tracking continues to follow only the primary selection")
```

`EditorTextSystem.selectedRange` is **not removed** — it becomes a computed property over `selectionSet.primaryRange` so every existing consumer (`EditorTextSystem+DocumentReplacement`, `TextFilterCoordinator`, session restore) keeps compiling and behaving identically for the single-selection case, which remains the overwhelmingly common one.

### 7.2 Multi-cursor typing (new)

```
User types a character with 3 active selections
  → EditorView.Coordinator.textView(_:shouldChangeTextIn:replacementString:)
    → guard !hasMarkedText/no marked-range intersection (existing IME gate, reused verbatim)
    → guard selectionSet.isMultiple else { return true /* fall through to native single-range handling, unchanged */ }
    → build one EditorEditTransaction: one TextReplacement per selection range, all with the same replacementString
    → EditorTextSystem.apply(transaction)  (one undo group, one publication — §6.3)
    → return false (suppress the native single-edit path; we already applied it)
```

### 7.3 Fenced-code/front-matter gating (new; extends existing E10 dispatch)

```
Return/Tab/typed-character hook (EditorView.Coordinator, existing entry points)
  → existing: format check (document.format.id == "markdown")
  → NEW: FencedRegionClassifier.classify(text: NSString, atUTF16Offset: caretOffset) -&gt; .prose | .fencedCode | .frontMatter
       (bounded backward scan from caret to nearest preceding unmatched fence/`---` delimiter pair;
        never touches MarkdownEngine/SourceMap; matches E10's "local, synchronous, no full parse" rule)
  → if .fencedCode or .frontMatter: Markdown-specific list/blockquote/delimiter assists do NOT run;
     LanguageEditingProfile-driven general pairing/indent DOES run (using the fenced language's own
     profile where the fence carries a language tag, else `.plainText`)
  → if .prose: existing Markdown assist path, unchanged
```

## 8. Concurrency and cancellation

- `EditorLineIndex`, `EditorSelectionSet`, `EditorEditTransaction`, `LanguageEditingProfile`: plain `Sendable` value types, mutated only on the main actor inside `EditorTextSystem`'s existing edit call sites. No new actor.
- `WorkspaceFileIndex` (TextSearch): an `actor`, built/rebuilt via `Task.detached` off the main actor, exactly mirroring `FileTreeModel.contents(_:)`'s existing `Task.detached { try self.reader.contents(of: url) }.value` shape. A generation counter (mirroring `FileTreeModel.generation`) invalidates any in-flight build whose root has since changed.
- Current-document regex search: runs off-main for anything above a small buffer-size threshold (exact threshold decided in Slice 5, informed by the performance budget in §11), with a query-generation counter so a stale query's results are never published over a newer one's — the same "stale generation guard" pattern `FileTreeModel.reload`/`OutlineController` already use.
- Folder search: cancellable per-search-session `Task`, streams results incrementally (not one batch at completion), bounded accumulation (explicit per-file and total caps per the epic's required behaviour list).
- Replace-in-folder: search produces immutable per-file snapshots (already-read `FileSnapshot`s, per §2.1's `FileStore` guarantee) before any write begins; each write is independently revalidated at publication time via `expectedRevision`, exactly like a normal document save — no global lock across files, no assumption that the whole batch succeeds atomically.

## 9. Failure model

- **Invalid regex** (current-document or folder search): surfaced as a visible, localized inline diagnostic (`SearchQueryError.invalidRegex`) — never an empty-result state indistinguishable from "no matches."
- **Pathological/slow regex:** cancellable; a cancelled search leaves the document/results pane in its last-good state, never a partial/corrupt result set.
- **Multi-cursor edit where one range would produce invalid UTF-16 (e.g. splitting a surrogate pair):** the whole transaction fails closed (no partial application) — `EditorEditTransaction`'s Debug-fatal/Release-drop validation (§6.3) is the boundary; a Release build never applies a corrupt subset.
- **Reopen Using Encoding… fails to decode:** current document completely untouched (invariant #7); the error is surfaced, no metadata is updated.
- **Save With Encoding… would be lossy:** the write does not happen; disk and document metadata are both unchanged (mirrors `FileDocument.saveAs`'s existing lossless-check-before-write discipline, generalized to plain save).
- **Replace-in-folder target changed since search:** that file is skipped and reported in the summary, exactly like a normal save's `.fileChangedDuringRead`/`reconcileSaveConflict` handling — never silently overwritten, per invariant #6.
- **Symlink loop during workspace indexing:** the walker's own visited-physical-identity guard (§2.1, new — no existing precedent) terminates that branch; the index build completes with the rest of the tree, not a hang or crash.
- **`.tex`/`.latex` with no available highlighter:** falls back to plain-text-styled rendering with correct format identity (never Markdown, never a crash) — see §9.6's evidence-based decision.
- **Snippet body referencing `${clipboard}` with an empty/non-text clipboard:** expands to an empty string at that position, never a crash or a placeholder token leaking into the document.

## 10. Security and trust boundary

- Folder search/replace reads/writes only within an already-user-granted folder root (`FolderAccessScope`), using the same access grant the sidebar already holds — no new capability is requested, no telemetry, no document content ever leaves the process (unchanged product invariant, `RELEASE_HARDENING.md` §1.1).
- Snippets are plain, versioned JSON in Application Support, atomic writes (mirroring `WorkspaceSessionStore`'s existing atomic-write pattern) — no shell interpolation, no executable content, per the epic's explicit exclusion.
- `Reopen Using Encoding…`/`Save With Encoding…` operate only on already-open, already-permitted files; no new file-system capability.
- The `.tex`/`.latex` format addition does not enable TeX *compilation* (explicitly out of scope) — it is source-text editing only, so it introduces no new subprocess/execution trust boundary.

## 11. Resource and performance budgets

Restated from the epic issue, with the evidence layer each is measured at:

| Budget | Target | Evidence layer |
|---|---|---|
| Gutter/status caret update | &lt; 8 ms main-actor work | package unit benchmark (synthetic keystroke loop) |
| 100-caret edit, 1 MB document | &lt; 50 ms excluding highlighter debounce | package integration test, mirroring `EditorPerformanceTests`' existing shape |
| Literal search, 10 MB text | &lt; 200 ms off-main | package benchmark, `TextSearchEngine` directly |
| Quick Open top-result refresh, 100k paths, after indexing | &lt; 30 ms | package benchmark, `WorkspaceFileIndex` directly |
| 100k-path index build | off-main, visible progress/ready state | integration test + manual Release observation |
| Folder search | streams first results, bounded accumulation | integration test with a large synthetic tree |
| Gutter draw | visible line numbers only, never whole-document layout | extends `EditorPerformanceTests.open10MBLazy`'s fragment-count assertion pattern to the gutter's own draw path |

**E05 inherited debt (§2.1, binding on this epic, not merely inherited-and-restated):** the existing `HighlightPerformanceTests` must be corrected to actually run and assert against Release-configuration numbers, not restate an unverified claim. This requires either (a) adding a Release-configuration package-test CI step (mirroring the "Build app + CLI (Release)" step's existing precedent, extended to `swift test -c release` or equivalent for the affected suite), or (b) if a Release package-test run proves infeasible in CI for a concrete, documented reason, recording a real local-Mac measurement with the exact command used, per `EPIC_STANDARD.md` §3.11's "unit/package benchmark vs. complete app-path Release measurement vs. manual observation" distinction — but the *current* state (an 8-second Debug ceiling standing in for an unenforced 50 ms/500 ms/8 ms claim) is not an acceptable release-evidence disposition and must change materially, not just be re-documented.

## 12. Accessibility and localisation impact

- All new UI (gutter, status bar, Quick Open panel, folder-search results, encoding/EOL menus, snippet editor) ships with accessibility labels/identifiers from the same slice that introduces the UI, per `EPIC_STANDARD.md` §3.12 ("feature epics own their basic accessibility... not a dumping ground for E15/E16").
- New user-facing strings land in the existing `Localizable.xcstrings` app-target catalog in the same slice as the UI that introduces them (per the epic's own §"Settings/localisation" note) — this repo's established String Catalog pattern (see `planning/epic-16-implementation.md`) is reused unchanged; no new catalog infrastructure is needed since the app target's catalog and resource-bundle wiring already exist.
- Because E16's *final* string freeze is deferred until after E22/E23/#115 (per the 2026-09-21 sequencing), E22 does not need to request a localisation re-verification pass mid-epic — but must not leave any new string un-cataloged, since the eventual post-#115 delta-extraction pass (§13) will audit for exactly that.
- Current-line highlighting (§2.1/§2.2) must not be the *only* indicator of the active line (existing acceptance criterion: "distinguishable without relying on color alone") — the implementation must also consider a stronger gutter-number weight/style for the current line, decided concretely in Slice 2.

## 13. Export and interoperability

- Line-number gutter, status bar, invisibles, and multi-cursor are editor-only presentation; none of them affect the durable document text or any export path.
- EOL/encoding conversions are explicit user actions that change the *saved bytes* exactly once, at the moment of the action — they do not retroactively alter Export, which already reads the live in-memory text (unaffected by these changes) and writes via its own, unrelated `ExportService` path.
- `.tex`/`.latex` files get no preview/export capability beyond what any other syntax-highlighted, non-Markdown, non-previewable source format already has (plaintext-style editing) — this is a deliberate exclusion (§ "Explicitly out of scope" in the issue: no TeX compilation), not an oversight.
- Snippets and general-format editing profiles have no export-time representation — they are editor-only conveniences.

## 14. Test and evidence matrix

| Requirement | Evidence |
|---|---|
| `EditorLineIndex` correctness (LF/CRLF/CR/Unicode/no-final-newline) | package unit tests, `EditorCoreTests` |
| `EditorSelectionSet` normalization/clamping/AppKit bridging | package unit tests |
| Multi-cursor typing/paste/delete/indent, one undo group | package integration tests (real `NSTextView`, mirroring `EditingAssistIntegrationTests`' existing shape) |
| Fenced-code/front-matter gating (adversarial: nested/tilde/backtick fences, unterminated mid-edit, caret crossing boundary) | package unit tests, new adversarial fixture set |
| `TextSearchEngine` literal/regex/case/whole-word/invalid-regex/Unicode folding | package unit tests |
| `WorkspaceFileIndex` fuzzy ranking, symlink-loop safety, 100k-path performance | package unit + performance tests |
| Folder search streaming/caps/cancellation | package integration tests with a synthetic large tree |
| Replace-in-folder conflict/skip/encoding/EOL preservation | package integration tests reusing `FileStore`'s existing conditional-publication test patterns |
| Encoding reopen/save round-trip, lossy-write rejection | package tests extending `TextRoundTripFidelityTests`' existing style |
| EOL detection/conversion, mixed-EOL fidelity | package tests, same file |
| `.tex`/`.latex` format registration, no-Markdown-leak, round-trip | package tests extending `FormatRegistryConsistencyTests` |
| Snippet expansion (selection/clipboard/$0/multi-cursor) | package unit tests |
| Command-palette consistency (#117) | a new consistency test asserting every intentionally-eligible `WorkspaceCommands` entry has a corresponding `AppPaletteCommand`, with explicit, named exclusions — replacing the current zero-coverage gap |
| E05 Release performance evidence | corrected `HighlightPerformanceTests` (or documented local-Mac measurement) — see §11 |
| Critical UI journeys (multi-cursor, Quick Open, folder search, Go to Line) | genuinely executed XCUITest evidence where a runnable macOS GUI environment is available this session; otherwise honestly disclosed as unverified, matching this session's established practice for `MacDown2UITests` throughout E15/E16, never inferred as passed |
| Existing green suites remain green | full package + app-target regression run before every slice merges |

## 15. Adversarial corpus

Restated and made concrete from the epic issue's own "Adversarial requirements" section — this document does not weaken any of it:

- **Multi-cursor:** overlapping/adjacent selections, duplicate cursors at the same offset, emoji/CJK/combining-character boundaries, CRLF boundaries, first/last line, paste, undo/redo, interaction with auto-pair/comment/indent, an external full-document replacement arriving mid-multi-cursor-session, IME marked text, 100+ simultaneous cursors.
- **Search:** empty query, zero-width regex match, invalid regex, a deliberately slow/catastrophic-backtracking regex (cancellation must actually free the main actor), Unicode case folding, CRLF/mixed-EOL documents, a single very long line (no line-based assumption may break), binary/non-decodable files encountered during folder search, permission-denied files, symlink loops, the folder root changing mid-search, a target file mutated between search and replace, and result-cap truncation.
- **Encoding/EOL:** UTF-8 with/without BOM, UTF-16 LE/BE, Windows-1252, MacRoman, a representative CJK legacy encoding Foundation supports, an unrepresentable-on-save character, malformed bytes, a BOM that contradicts the selected encoding, mixed EOL within one file, no-final-newline fidelity, and an external edit landing concurrently with an encoding conversion.
- **Gutter/status/invisibles:** wrapped lines, a very long single line, a 10 MB file, empty document, first/last line, theme switch, light/dark/increased-contrast, multiple selections spanning many lines, CJK/emoji column counting, hidden/shown toggling, and confirmation that invisibles never trigger the legacy TextKit 1 fallback path.
- **Fenced-code/front-matter (new, from §2.1's E10 follow-up):** caret moving into/out of a fence via arrow keys vs. click vs. programmatic jump, a pasted fence, a blockquote-nested fence, a list-nested fence, front matter followed immediately by a fence, CRLF-delimited fences, and a very large document (the classifier's bounded backward scan must stay bounded, not degrade to a document-length scan).

## 16. Expected files and symbols

**New:**
- `MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorLineIndex.swift`
- `MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorSelectionSet.swift`
- `MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorEditTransaction.swift`
- `MacDown2/Packages/MacDownKit/Sources/EditorCore/LanguageEditingProfile.swift`
- `MacDown2/Packages/MacDownKit/Sources/EditorCore/FencedRegionClassifier.swift`
- `MacDown2/Packages/MacDownKit/Sources/TextSearch/*` (new package target)
- `MacDown2/Packages/MacDownKit/Sources/FileCore/LineEndingProfile.swift`
- New `EditorCore`/app-target files for the gutter, status bar, Go to Line panel, invisibles overlay, Quick Open panel, folder-search UI, replace-in-folder preview UI, encoding/EOL menus, syntax-override menu, snippet store/editor — exact filenames decided per-slice.

**Modified:**
- `EditorTextSystem.swift` and its extensions (selection, apply, configuration).
- `EditorConfiguration.swift` (`showsInvisibles` becomes real).
- `DocumentEditorSplitView.swift`/`DocumentEditorSplitView+AppSettings.swift` (format-neutral `editingAssists`/profile wiring, replacing the current Markdown-only gate with a gate that still special-cases Markdown's *extra* behavior but no longer disables the *general* profile for every other format).
- `WorkspaceCommands.swift` (Cmd-D disambiguation, new commands, Go to Line, Insert Snippet, Reopen/Save With Encoding, EOL conversion, syntax override).
- `AppPaletteCommand.swift` (palette-consistency mechanism).
- `WindowCoordinator*.swift` (Quick Open origin-window pattern, first-responder-aware Cmd-D).
- `FileFormatRegistry.swift`, `FormatManifest.swift`, `GrammarRegistry(+Factories).swift`, `project.yml` (`.tex`/`.latex`).
- `FileEncodingMetadata`'s validation (`FileEncoding.swift`).
- `HighlightPerformanceTests.swift` (real Release budgets).
- `MarkdownParseOptions` (five-field disposition) and its settings-pane UI.
- `EditorChrome`/`NeonSyntaxHighlighter.applyChrome` (current-line consumption) and both bundled theme JSON files (real current-line values) — coordinated with E23's semantic theme palette per the epic's own note that E23 owns the palette while E22 owns making the *role* real.

**Must not change without an explicit escalation, per `EPIC_STANDARD.md` §6:** `FileStore`'s conditional-publication algorithm itself, `FileDocument`'s recovery-epoch identity scheme, `RecentFolderRoots`'/`FolderAccessScope`'s bookmark semantics, `ContributionRegistry`'s document-content pipeline (unrelated to this epic), and any existing test's assertion threshold being *weakened* to make a new feature pass.

## 17. Implementation slices

Per the owner's explicit technical-dependency-order instruction, slices are ordered foundations-first rather than strictly following the epic issue's own scope-area numbering (which interleaves foundation and UI within each scope area). Each slice is one or more independently reviewable PRs; a slice does not merge until its own tests/lint/build evidence is green and a hostile review of that slice's diff has run and its findings are resolved.

### Slice 1 — Pure foundations (no UI, no AppKit wiring)

**Goal:** land `EditorLineIndex`, `EditorSelectionSet`, `EditorEditTransaction`/`TextReplacement`, the `TextSearch` package skeleton (`SearchQuery`/`SearchOptions`/`SearchMatch`/`TextSearchEngine` + an empty `WorkspaceFileIndex`/`WorkspaceSearchEngine` shape), fuzzy-scoring foundations, and `LanguageEditingProfile` (data type only, not yet consumed) as fully tested, unintegrated types.

**Dependencies:** none beyond current master.
**Ownership:** `EditorCore` + new `TextSearch` package only. No changes to `DocumentEditorSplitView` or any app-target file. `EditorView`/`EditorTextSystem` themselves are otherwise untouched, with one narrow, already-reconciled exception: `EditorTextSystem.isApplyingMultiRangeTransaction` and the corresponding one-line guard addition to `EditorView.Coordinator.textDidChange`, both required for `EditorEditTransaction.apply(_:)` — one of this slice's own stated deliverables — to publish its SwiftUI binding once per transaction instead of once per range. This was discovered while implementing the slice, is documented in full in §6.3, and does not widen the slice into Slice 2's UI-integration territory (no gutter/status-bar/invisibles wiring landed here) — it is the minimum change needed for a Slice 1 deliverable to be correct at all.
**Tests:** full unit coverage per §14's first six rows, run as pure package tests (`swift test`) — no app-target/XCUITest dependency for this slice.
**Verification:** `swift build && swift test --no-parallel` for `MacDownKit`; `swiftformat --lint`/`swiftlint --strict`.
**Stop condition:** if any of these types cannot be built without touching `EditorTextSystem`'s existing public API beyond the one exception above, in a way not anticipated by §6, stop and reconcile this document before proceeding — do not silently widen scope into Slice 2's territory.

### Slice 2 — Line index + editor chrome integration

**Goal:** wire `EditorLineIndex` into `EditorTextSystem`'s edit path; ship the line-number gutter, status bar, Go to Line/Column, and real TextKit-2-safe invisibles (making `showsInvisibles`/`EditorChrome.invisibles` genuinely consumed).
**Dependencies:** Slice 1.
**Tests:** the gutter/status/invisibles adversarial corpus (§15); the viewport-laziness performance budget (§11) as an automated assertion.

**Split into two sequential PRs, decided at the point this slice began** (per `EPIC_STANDARD.md`'s "detailed contract fixed when the slice starts" convention, same as §6.4/§6.5): a fresh baseline read of `EditorTextSystem`, `EditorView`, and the (nonexistent) gutter/status-bar/Go-to-Line code (recorded in §6.6 below) showed the line-index wiring alone has real correctness subtlety — it must update once per atomic edit even inside an `EditorEditTransaction`'s N-range loop (which `EditorView.Coordinator.textDidChange`'s existing multi-range publication suppression would otherwise hide N−1 of), it must handle E10 assist's edit-interception (a vetoed outer edit whose nested internal edit is the one that actually lands), and it must do all of this without a full-document string copy per keystroke — while the remaining three deliverables (status bar, Go to Line, invisibles) are comparatively independent, self-contained UI additions. Bundling five non-trivial, differently-risky changes into one PR would repeat exactly the "monolithic change" failure mode this epic's own owner directive warns against at the epic level, just one level down. So:
- **Slice 2a** — `EditorLineIndex` wiring (§6.6) + the line-number gutter, the one deliverable that both consumes the wiring directly and gives it a visible, testable surface end-to-end.
- **Slice 2b** — Go to Line/Column and a status bar scoped to fields with no forward dependency on later slices (§6.7), once 2a is merged and proven.
- **Slice 2c** — TextKit-2-safe invisibles rendering (§6.7), split out from 2b for the same "don't bundle differently-risky changes" reason 2 was split into 2a/2b: invisibles is novel, character-glyph-level AppKit drawing with no existing precedent in this codebase, unlike 2b's two precedent-following, low-risk deliverables.

### Slice 3 — Selection foundation and multi-cursor

**Goal:** wire `EditorSelectionSet` as `EditorTextSystem`'s selection source of truth (§7.1); implement Option-click add/remove, add-cursor-above/below, rectangular selection, Escape-collapse, and route typing/paste/delete/indent through `EditorEditTransaction`. Resolve Cmd-D (occurrence selection vs. Folder Duplicate) via the `commandStateRevision`/first-responder pattern (§2.1).
**Dependencies:** Slice 1.
**Tests:** the full multi-cursor adversarial corpus (§15); IME safety tests; the 100-caret/1MB performance budget.

### Slice 4 — Core text commands + language profiles

**Goal:** the ten built-in transforms (Duplicate/Delete/Move/Join/Sort/Dedupe/Trim/case/indent/comment-toggle); generalize the pairing/indent engine via `LanguageEditingProfile` to every format; implement the fenced-code/front-matter classifier and gate Markdown-specific assists behind it (closing the E10 inherited debt item).
**Dependencies:** Slices 1-3 (needs `EditorEditTransaction` for multi-cursor-aware transforms).
**Tests:** fenced-code/front-matter adversarial corpus; format-neutral pairing/indent tests across every registered `FileFormat`.

### Slice 5 — TextSearch + current-document search

**Goal:** real regex/literal engine behind current-document Find/Replace UI, replacing reliance on stock `NSTextFinder` for anything beyond its existing menu-level trigger wrapper (`EditorFind.swift` — which continues to exist for the plain show/hide/toggle-interface calls, but the actual match/replace logic becomes MacDown 2's own per the epic's explicit "stock NSTextFinder is enough" reversal).
**Dependencies:** Slice 1 (`TextSearch` types); Slice 3 (select-matches-into-multi-selection needs `EditorSelectionSet`).
**Tests:** search adversarial corpus; literal-search-in-10MB performance budget.

### Slice 6 — Workspace index + Quick Open + recents

**Goal:** `WorkspaceFileIndex` real implementation, Cmd-P Quick Open panel (mirroring `CommandPalettePanel`'s origin-window-capture idiom), Open Recent File menu.
**Dependencies:** Slice 1 (`TextSearch` fuzzy scoring).
**Tests:** 100k-path indexing/query performance budgets; symlink-loop safety.

### Slice 7 — Folder search + safe replace

**Goal:** folder-wide search UI, streaming results, filters, and Replace in Folder with the full preview/revalidate/skip-on-conflict safety model (§9, §4 invariant #6).
**Dependencies:** Slice 6 (`WorkspaceFileIndex`); Slice 5 (`TextSearchEngine` reuse).
**Tests:** replace-in-folder adversarial corpus; conflict/skip evidence reusing `FileStore`'s existing conditional-publication test patterns.

### Slice 8 — Encoding/EOL controls

**Goal:** Reopen Using Encoding…, Save With Encoding…, broadened `FileEncodingMetadata` validation, `LineEndingProfile`, EOL conversion commands.
**Dependencies:** none from this epic (can proceed in parallel with Slices 2-7 once Slice 1 lands, since it touches `FileCore`/app-target menus, not `EditorCore`'s selection/edit machinery) — sequenced here per the owner's stated preference order, not a hard technical dependency.
**Tests:** full encoding/EOL adversarial corpus; `TextRoundTripFidelityTests` regression.

### Slice 9 — Syntax override + snippets + `.tex`/`.latex` + `MarkdownParseOptions`/#117 disposition

**Goal:** per-document Syntax Mode override; native snippet system; `.tex`/`.latex` format registration per the evidence-based §9.6 decision; remove/recast the five inert `MarkdownParseOptions` fields; close #117's command-palette consistency item.
**Dependencies:** Slice 4 (`LanguageEditingProfile` needed for TeX mechanics and snippet syntax-scoping).
**Tests:** snippet expansion corpus; `FormatRegistryConsistencyTests` extension for `.tex`/`.latex`; the new palette-consistency test.

### Slice 10 — Orthogonal hardening

**Goal:** the full adversarial/performance/accessibility pass across every slice's surface together (interactions between multi-cursor + search, multi-cursor + snippets, encoding conversion + external edit, etc.), plus the corrected E05 Release performance evidence (§11).
**Dependencies:** Slices 1-9.

### Slice 11 — Release re-gate

**Goal:** re-run affected E15 evidence rows, produce E16's post-E22 localisation delta (extraction + fr/pl/ja translation + pseudo-localisation, per `epic-16-implementation.md`'s established workflow) **only if** the owner has by then also completed E23 per the current sequencing (E22 → identity re-freeze → E23 → #115 → final E16 freeze) — otherwise this slice records E22's own string/UI delta honestly as a partial update to the interim baseline and defers the *final* freeze declaration to after E23/#115, per §12 above. Confirm zero unresolved P0/P1 introduced by E22 before considering the epic release-complete.

## 18. Definition of Done and residual risk

Per `EPIC_STANDARD.md` §4, plus the epic issue's own acceptance criteria (both the original ~19-item list and the "Additional acceptance criteria" from the 2026-09-21 inherited-debt amendment) — not restated verbatim here to avoid drift between two copies; this document's binding completion gate is: **every checkbox in the epic issue is either checked with linked evidence, or explicitly, individually dispositioned (FIXED/PROVED/REJECTED-FOR-1.0) in `RELEASE_EVIDENCE.md`, before E22 is considered release-complete for the #115 gate.**

**Consciously deferred / residual risk to track as follow-up issues, not silently dropped:**
- Same-document split view remains explicitly out of scope (architectural — one `NSTextView` per document).
- The remaining priority locales beyond fr/pl/ja (per E16's existing disposition) are not this epic's responsibility to add.
- If §9.6's evidence-based review concludes no safe `.tex`/`.latex` highlighter dependency is currently integrable, the plain-text-styled fallback is the recorded, tested, deliberate 1.0 disposition — not a placeholder for later work, unless the architecture review itself identifies a concrete follow-up path.
- Exact fuzzy-ranking formula, gutter/status SwiftUI-vs-AppKit ownership split (§5.2), and the precise Cmd-D/first-responder event set (§2.1's "purely-keyboard focus transfer is not currently in `shouldRefreshCommandState`'s switch" open question) are intentionally left to their owning slice rather than pre-decided here, per `EPIC_STANDARD.md`'s Layer 2/Layer 3 split — each will be recorded as an addendum to this document when that slice lands.

## Changelog

- 2026-09-21: Initial architecture, authored against baseline `95e4f60` before any implementation slice began.
- 2026-09-21: Slice 1 landed (PR #123). Reconciled this document against three real bugs an external automated review of that PR found and that were fixed, not merely re-documented: `EditorLineIndex`'s incremental rescan lacked a leading margin (§6.1), `EditorSelectionSet.indexClosest` used inclusive rather than half-open containment (§6.2), and `EditorEditTransaction`'s overlap/bounds validation used `precondition` (traps in Release too, contradicting this document's own "Release drops, doesn't crash" contract) with zero test coverage of the invalid-input path (§6.3). Also reconciled §17's Slice 1 "no changes to `EditorView`/`EditorTextSystem`" boundary with §6.3's already-documented, narrow, required exception for `isApplyingMultiRangeTransaction`, and closed a `WorkspaceFileIndex`/`DirectoryWalker` gap where symlinked directories were misclassified as files (§2 baseline).
- 2026-09-21: Slice 1 owner review corrected `EditorEditTransaction`'s validation from a partial "valid prefix" fallback to true all-or-nothing rejection of the whole transaction (§6.3's third correction), fixed a crash in the rewritten validator (`1 ..< 0` on an empty transaction) and a flaky supersession test in `WorkspaceFileIndexTests`, and closed the requested test matrix (empty/single/multi-element, overflow, first/middle/last invalid-position, mounted-`NSTextView` zero-mutation regressions). PR #123 merged to `master` at `338f800` with 1401/1401 package tests passing and the complete GitHub CI matrix green. Slice 1 is closed; Slice 2 (editor chrome: gutter, status bar, Go to Line/Column, invisibles) begins next per §17.
- 2026-09-24: Slice 2a landed (PR #124, four review rounds against real bugs, each fixed rather than merely re-documented). `EditorTextSystem.noteIncrementalEdit`/`rebuildLineIndex` (§6.6, new `EditorTextSystem+LineIndex.swift`) read `assistTextSource` (the live `NSTextStorage`-backed string) instead of `text`/`textView.string`, avoiding the O(document length) materialization the codebase's own `EditorTextSystem+EditingAssists.swift` already documents as "last resort only." `EditorGutterView` (new `NSRulerView` subclass) shipped with accessibility metadata (identifier `editorGutter`, role `.group`, a localized label) from the same slice per §12, and its viewport-bounded draw path (`EditorTextSystem+Gutter.swift`'s `enumerateVisibleLineFragments`) is now covered against a 10 MB document, not just a 50-line crash-safety smoke test. Three separate sites hit the same undo-manager-identity bug class — `EditorTextSystem.undoManager` resolves to a throwaway `fallbackUndoManager` until the text view is mounted in a real window, then switches identity to the window's real manager — in `EditorTextSystem`'s own observer, `EditorView`'s gutter-redraw observer, and (found by a hostile review of the fix itself) a test that could not have detected any of this because `dismantleNSView` never actually fires via SwiftUI's view-identity-switch teardown in a headless test process; the final test calls `dismantleNSView(_:coordinator:)` directly on the real `scrollView`/`coordinator`, which exercises the identical production code path deterministically. Also fixed: `updateNSView` recomputed gutter thickness before applying model text instead of after; `EditorTextSystem.init` scanned `initialText` twice (once directly, once again inside `setText`'s rebuild); and `EditorGutterView.updateThickness` measured only "0"'s glyph width, which could clip a wider digit in the proportional/display fonts the Editor settings' unrestricted font picker allows (fixed by measuring the widest of "0"-"9", regression-tested against "Bradley Hand"). Added a dedicated `<8 ms` gutter/caret-update benchmark isolating `EditorLineIndex.applying` + `updateThickness()` from TextKit layout, per §11's "Gutter/status caret update" row (a distinct, narrower budget than the existing 50 ms whole-keystroke tests); made it a best-of-5-trials minimum after one CI run flaked at 9.1 ms/op on shared runner hardware against a consistent ~5-6 ms/op locally — the 8 ms threshold itself was not weakened. PR #124 merged (squash) to `master` at `4ebf8b6` with 1428/1428 package tests passing and the complete GitHub CI matrix green on the final SHA. Slice 2a is closed.
- 2026-09-24: Wrote the Slice 2b/2c contract (§6.7) before implementation began, per a fresh baseline read against `master` at `a2b52c9`. Split former Slice 2b (status bar, Go to Line/Column, invisibles) into 2b (Go to Line/Column + a status bar scoped to fields with no forward dependency on Slices 3/8/9) and 2c (TextKit-2-safe invisibles, novel character-glyph-level AppKit drawing with no existing precedent, split out for the same reason Slice 2 itself was split into 2a/2b) — see §17. Also recorded that the epic issue's full status-bar item list (multi-selection count, line-ending state, encoding, syntax mode) is not fully closed by Slice 2b alone; those four items are deferred to their owning slices by design, appended later to the status bar's own extensible item list rather than stubbed now. Slice 2b begins next per §17.
