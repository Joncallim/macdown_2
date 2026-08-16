# MacDown → Swift/SwiftUI Migration Plan

> Status: **approved direction** · Scope: full rewrite as a **new product** · Target: **macOS 26+ for 1.0**

This document is the single source of truth for the rewrite roadmap. Epics live in
`planning/epics/` and are tracked as GitHub issues on `Joncallim/macdown_2`.
`planning/EPIC_STANDARD.md` defines the mandatory readiness, architecture,
execution, completion and human-readability contract for new epic work.

> **Amended 2026-07-22 (mid-point check-in, #28):** D2 reversed to native
> `NSWindow` tabs (see below); branch strategy updated (`master`, not
> `rewrite/main`); O4 resolved; EPIC-18 (live external-file changes) added as
> a required pre-dogfooding capability.
>
> **Amended 2026-08-16 (technical-writing/product-completion review):** math and
> text-authored diagrams are first-class macOS 1.0 capabilities; E14 is narrowed
> to contribution/extension infrastructure; E19-E21 own math and diagrams; a
> feature-complete gate now precedes final polish; iPad implementation is
> explicitly deferred until after the completed macOS 1.0 release; final product
> naming is reopened while `MacDown 2` remains the working repository/app name.

---

## 1. Vision

A fast, native, workspace-style Markdown, code and technical-writing editor for
macOS 26 "Tahoe": Swift 6 + SwiftUI, Liquid Glass interface, tabbed editing,
collapsible folder browser, per-document content browser (outline), first-class
support for JSON, HTML and other popular languages, and text-authored math and
technical diagrams that render beautifully without making the durable document
opaque.

The product remains text-first: Markdown/source is the durable, readable,
diffable representation; previews, equations and diagram graphics are derived
outputs.

## 2. Locked Decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Deployment floor | **macOS 26+ for macOS 1.0** (Xcode 26 SDK, Swift 6, Liquid Glass automatic; no `UIDesignRequiresCompatibility`) |
| D2 | Tab model | **Native `NSWindow` tabs** — one window = one document, grouped by AppKit tab groups; `WindowCoordinator` owns the pool, each window hosts its own `WorkspaceModel` + sidebar. *(Amended at the mid-point check-in #28: the original "in-app tabs in a single window" plan was superseded by the implementation, which proved native tabbing composes fine with a per-window sidebar and gets dedupe, dirty-close, and session restore with far less custom UI.)* The **content browser** (heading outline) still ships in the sidebar (E08) |
| D3 | Editor | **Custom NSTextView + TextKit 2** wrapped in `NSViewRepresentable`, **tree-sitter** highlighting (via SwiftTreeSitter). Priority: fastest, smoothest experience |
| D4 | Markdown preview | **Native SwiftUI via Textual** for ordinary Markdown (no WKWebView for Markdown); first-party derived content such as math/diagrams uses explicit contribution/renderer seams rather than turning the Markdown preview into a web page |
| D5 | Identity | **New product** — final public name, bundle ID, icon and appcast must be chosen before E17. `MacDown 2` / `com.joncallim.macdown2` are working development identifiers, not a permanently locked brand decision. MacDown fork serves as reference + resource donor |
| D6 | Extensions/contributions | macOS 1.0: internal `PreviewContribution` infrastructure + user **text-filter commands** (stdin/stdout scripts). E14 owns the safe seam and TOC/text-filter capability; E19 owns production math; E20 owns diagram platform + Mermaid; E21 adds D2/Graphviz/WaveDrom. Post-1.0: evaluate JavaScriptCore extension API. **Never** resurrect NSBundle in-process loading |
| D7 | Sandboxing | **Unsandboxed** for now (direct distribution). `FileTreeModel` still designed around security-scoped URLs so sandboxing is additive later |
| D8 | iPad sequencing | **No iPad implementation before the completed macOS 1.0 release.** Do not add UIKit targets or speculative portability layers during the Mac roadmap. New engine code should avoid gratuitous AppKit coupling when platform-neutral code is equally simple; actual platform extraction/porting is post-release work |

## 3. Product Shape

```text
┌────────────────────────────────────────────────────────────────┐
│ Native NSWindow tab bar (AppKit: title / dirty dot / reorder)  │
├────────────────────────────────────────────────────────────────┤
│ Toolbar (glass)                              [sidebar toggle]  │
├──────────────┬──────────────────────────────┬──────────────────┤
│ SIDEBAR      │                              │                  │
│ (collapsible,│  Editor                      │  Preview         │
│  per window) │  NSTextView + TextKit 2      │  Textual (MD)    │
│              │  + tree-sitter highlight     │  + math/diagrams │
│ ▾ FOLDER     │                              │  WKWebView(HTML) │
│   browser    │                              │  Outline (JSON)  │
│ ──────────── │                              │                  │
│ ▾ CONTENT    │                              │                  │
│   browser    │                              │                  │
└──────────────┴──────────────────────────────┴──────────────────┘
```

- **Scene model (as built):** `AppDelegate` + `WindowCoordinator` own a pool of
  `NSWindowController`s — one window per document, grouped as native tabs. The
  SwiftUI `WindowGroup` scene exists only to host the command/menu structure.
  Each window hosts its own `WorkspaceModel`; `TabStore` survives as the
  per-window single-document holder and session-restore seam. **Not**
  `DocumentGroup`.
- **Document lifecycle is re-implemented** (no NSDocument): autosave-on-edit,
  dirty tracking, close-dirty prompts, session restore. This is a deliberate
  trade; it gets a dedicated state machine + heavy UI tests (EPIC-01/03/18).
- **Technical content is derived:** equations and diagrams retain text source in
  the document. Rendered artefacts are cacheable/disposable output and must not
  become the only copy of user-authored content.

## 4. Module Map (SwiftPM targets)

| Target | Responsibility | Replaces (ObjC) |
|---|---|---|
| `App` | `@main`, `WindowGroup`, commands, menus | MPMainController, MainMenu.xib |
| `Workspace` | WorkspaceModel, TabStore, session restore | — (new) |
| `FileCore` | FileStore (open/save/autosave), FileFormat registry, UTI decls | MPDocument (IO parts), Info.plist types |
| `FileTree` | Folder browser model: lazy loading, FS watching, CRUD | — (new) |
| `EditorCore` | NSTextView+TextKit2 representable, viewport layout, assists | MPEditorView, NSTextView+Autocomplete |
| `Highlighting` | SwiftTreeSitter engine, grammar registry, theme engine | peg-markdown-highlight |
| `MarkdownEngine` | swift-markdown parse actor, debounce, front matter, source-range index | MPRenderer, Hoedown, LibYAML |
| `Preview` | Format router: MD→Textual + first-party derived content, HTML→WKWebView, JSON→outline; scroll sync | WebView, templates, Prism |
| `OutlineUI` | Content browser (heading tree of active doc) | — (new) |
| `ExportService` | HTML + PDF export, templates, later math/diagram derived output | MPAsset, MPExportPanel…, handlebars |
| `AppSettings` | `Settings` scene + `@AppStorage` model | PAPreferences, MASPreferences, 5 XIBs |
| contribution/extension layer (E14 architecture decides final target name) | first-party preview contribution seam, text-filter commands | MPPlugIn (retired) |
| `CLITool` | swift-argument-parser launcher | macdown-cmd, GBCli |
| `Themes` | Ported editor/preview themes | Resources/*.styles, *.css |

Do not create new SwiftPM targets merely because the roadmap names a conceptual
area. Each epic architecture pass must justify target/module changes against the
then-current repository.

## 5. Technology Selections (verified July 2026 unless an epic re-verifies them)

| Concern | Choice | Notes |
|---|---|---|
| Markdown AST | `swiftlang/swift-markdown` 0.8.x (Apache-2.0) | cmark-gfm based; source ranges retained; **no incremental parse** — full re-parse is ms-cheap at current measured layers |
| cmark HTML (export) | `swiftlang/swift-cmark` 0.8.x | Maintained SwiftPM packaging of cmark-gfm |
| MD preview | `gonzalezreal/textual` 0.5.x (MIT) | Pre-1.0 — pin + wrap behind protocol. MarkdownUI is maintenance-mode: rejected |
| Editor highlighting | `ChimeHQ/SwiftTreeSitter` (MIT) + tree-sitter grammars | Incremental, O(edit) re-highlight |
| Attr-string highlighting (fallback) | HighlighterSwift (MIT) | Highlightr unmaintained: rejected |
| YAML front matter | `jpsim/Yams` | Replaces LibYAML + vendored YAML-framework |
| CLI | `apple/swift-argument-parser` | Replaces GBCli |
| Updates | Sparkle **2.x** (EdDSA) | New keys + new appcast (new product) |
| Localization | String Catalogs (`.xcstrings`) + Transifex | Migrate priority locales first |
| CI | GitHub Actions, `macos-26` runner | Travis config is Xcode 10.1-era: retired |
| Math renderer | **Not preselected here** | E19 must verify capability, licensing, accessibility, native-preview fit, export quality, cache/performance characteristics before locking a renderer |
| Diagram renderers | Mermaid first, then D2/Graphviz/WaveDrom if architecture verification passes | E20 proves one common renderer model; E21 separately verifies packaging/licensing/security/bundle cost for each additional engine |

**Dependency policy:** SPM preferred/required for Swift package dependencies.
Pin exact versions where practical. Wrap third-party UI/runtime dependencies
behind narrow internal protocols so churn does not leak across the app. Do not
bundle a large runtime merely to satisfy a roadmap noun; the owning epic must
justify security, licensing, bundle size and performance.

## 6. Epic Roadmap

### Milestones / phases

| Milestone/phase | Goal | Epics |
|---|---|---|
| **M1 — Skeleton** | App launches, opens/saves files in tabs | E00, E01, E02, E03 |
| **M2 — Editor** | World-class text editing + highlighting | E04, E05, E10 |
| **M3 — Markdown core** | Live native preview + content browser | E06, E07, E08 |
| **M4 — Workspace & formats** | Folder browser, JSON/HTML, export, settings, live external files | E09, E11, E12, E13, E18 |
| **M5A — Feature completion** | Safe contribution seam + first-class technical writing | E14, E19, E20, E21 |
| **Feature-complete gate** | Prove the complete Mac product before polish | all major macOS 1.0 features through E21 |
| **M5B — Polish & ship** | Whole-app polish/a11y, l10n, distribution | E15, E16, E17 |
| **Post-1.0** | Evaluate/implement iPad from a finished Mac product | future E22+ only after E17 release gate |

GitHub's existing `M5 — Polish & ship` milestone may continue to hold E14-E21
administratively; this document defines the logical ordering inside M5.

### Dependency graph

```text
E00 ─▶ E01 ─▶ E02 ─▶ E03 ─▶ E09
  │      │
  │      ├─▶ E04 ─▶ E05 ─▶ E10
  │      │
  │      └─▶ E06 ─▶ E07 ─▶ E08
  │                   │
  │                   ├─▶ E11 ─▶ E12 ─┐
  │                   │                 ├─▶ E19 ─┐
  │                   └────────▶ E14 ──┤       │
  │                                     └─▶ E20 ─▶ E21
  │
  └────────────────────▶ E13

E18: E01 + E03(as built) + E04; required document-safety/dogfood evidence

E19 + E21 + remaining Mac features
  ─▶ FEATURE-COMPLETE GATE
  ─▶ E15
  ─▶ E16
  ─▶ E17 / macOS 1.0 release
  ─▶ only then post-1.0 iPad work
```

The architecture pass for each epic must recalculate its actual dependencies
from the live repository rather than treating this diagram as a substitute for
inspection.

## 7. Repository, epic and branch strategy

- The rewrite lives on **`master`** of `Joncallim/macdown_2` (amended at #28;
  the original `rewrite/main` plan was retired when the rewrite was merged to
  master). The legacy ObjC app survives as a read-only porting source in
  `legacy-reference/`.
- One branch per epic: `epic/NN-short-name` → PR into `master`.
- Every new/materially revised epic follows `planning/EPIC_STANDARD.md`:
  - live GitHub issue = product contract;
  - current-master `planning/epic-NN-implementation.md` = binding engineering contract;
  - dependency-ordered implementation slices = worker execution contracts.
- Broad implementation does not begin until the Definition of Ready is met.
- PR merge requires CI/tests **and** the applicable Definition of Done evidence;
  green CI alone is not sufficient proof of user-facing correctness.
- Hand-offs/PR discussions may contain technical detail, but durable decisions
  and changed contracts must be reconciled into repository documentation.
- Workers stop and escalate when a false assumption requires unauthorised
  architecture, cross-module dependencies, changed product behaviour, weakened
  tests or edits outside the agreed ownership boundary.

### Human-readable history rule

Repository history is written for people first.

- Commit subjects describe the outcome in plain English. An epic/slice ID is
  traceability, not a description.
- PRs begin with what changes, why, how it works in ordinary language, what the
  owner should test, risks/limits and verification evidence.
- Architecture documents begin with an owner summary before symbols/data flow.
- Define non-obvious jargon; do not depend on an agent conversation to make a
  document meaningful.
- Avoid unexplained orchestration shorthand such as `E20 S3`, `wire seam`,
  `tail`, `plumbing`, `follow-up` or `agent changes` as the sole explanation.

The detailed rules and examples live in `planning/EPIC_STANDARD.md` and the
GitHub PR/epic templates.

## 8. Performance Budgets (acceptance thresholds)

| Metric | Budget | Verified in |
|---|---|---|
| Cold launch → interactive | < 1 s (M-series) | E00, re-checked E15 |
| Open 1 MB .md → text visible | < 300 ms | E04 perf test |
| Open 1 MB .md → fully highlighted | < 500 ms | E05 perf test |
| Keystroke → highlight update | < 50 ms | E05 perf test |
| Keystroke → preview refresh (debounced) | < 150 ms | E07 perf test |
| Folder with 10k entries → expand | < 200 ms | E09 perf test |
| Memory, 20 typical tabs | < 300 MB | E15 audit |
| Math/diagram rendering | epic-specific budgets required | E19-E21 Release/integration evidence |

> **Measurement caveat (#28):** some existing budgets were initially verified
> as package-level `swift test` benchmarks rather than complete application-path
> measurements. The full app path — NSTextView edit → string extraction → model
> update → observation → highlighting/preview/derived-content refresh — must be
> measured where a performance claim depends on it. README/release claims must
> not exceed the layer actually measured.

E19-E21 must explicitly separate cache/unit benchmarks from real Release-app
editing responsiveness in mixed technical documents.

## 9. Testing and evidence strategy

- **Framework:** Swift Testing for new package code; preserve existing XCTest/
  XCUITest where app/UI testing requires it.
- **Coverage per epic:** every acceptance criterion maps to named evidence in
  the implementation architecture.
- **UI tests (XCUITest):** use for end-to-end behaviour where package tests
  cannot prove the real app path, including document lifecycle, editor/preview
  publication, navigation and destructive/recovery flows.
- **Fidelity corpus:** real-world Markdown/export corpus in E12, extended by E19
  for math and E20/E21 for diagrams.
- **Adversarial corpus:** malformed, oversized, rapid-change and renderer-
  failure cases are planned before technical-content epics can close.
- **Release dogfooding:** perceived responsiveness and complete user journeys
  are checked in Release builds, not inferred from Debug feel.
- **Environment note:** all authoritative app builds/tests require a Mac with
  Xcode 26.

## 10. Risk Register (top items)

| Risk | Mitigation |
|---|---|
| Hand-rolled document lifecycle → data-loss bugs | Autosave-on-edit + explicit state machine + regression/UI tests (E01/E03/E18); recovery buffer; destructive-path dogfood |
| Textual pre-1.0 API churn | Pin version; `MarkdownPreviewing` protocol seam; WKWebView fallback remains scoped to HTML, not Markdown |
| SwiftTreeSitter grammar packaging friction | Grammar registry isolates build; add languages deliberately with tests |
| Whole-document parse/model publication cost | Measure complete path; optimise only measured bottlenecks; never market package benchmarks as app-path proof |
| Tab/session restore edge cases | Restore is best-effort; never blocks launch; corrupted-state coverage |
| Math/diagram runtime complexity | E14 separates contribution infrastructure; E19-E20 verify one capability at a time; E21 only adds additional engines after E20 proves the abstraction |
| Renderer security/licensing/bundle-size surprises | Each renderer receives an explicit architecture review before adoption; untrusted source gets the minimum capability needed |
| Feature creep before release | E21 is the final planned major macOS 1.0 feature epic; feature-complete gate freezes major features before E15/E16/E17 |
| Premature multi-platform work | D8 forbids iPad implementation before macOS 1.0; no speculative UIKit/portability layer during feature development |
| Opaque agent-generated history | EPIC_STANDARD + PR/issue templates + owner-first documentation/commit rules; comprehension is part of Definition of Done |
| New-product zero-day basics (signing, notarize, appcast) | E17 owns release pipeline; final product identity must be settled before appcast/signing/public release material is finalised |

## 11. Release Strategy

- `MacDown 2` remains the working development name until the final product name
  is chosen. Final name, icon, bundle ID, website and appcast identity are fixed
  before E17's public-release work.
- Private alpha after the core editor/Markdown path is trustworthy; sustained
  dogfooding continues throughout feature development.
- Major macOS 1.0 feature development ends at E21.
- The feature-complete gate then exercises the complete real application across
  document lifecycle, editing, formats, folders, preview, math, diagrams,
  export, settings and extension infrastructure.
- E15 performs whole-app polish/accessibility/performance after the feature
  freeze; E16 freezes/translates stable strings; E17 signs/notarises/distributes.
- macOS 1.0 is released only after E17's release gate.
- iPad implementation begins **after** that completed release, not in parallel.
- MacDown (ObjC) remains available; no forced migration. Optional preference/
  theme import remains an E13 decision.

## 12. Open Decisions (must resolve to unblock)

| # | Question | Blocks |
|---|----------|--------|
| O1 | Final public product name + final bundle ID. `MacDown 2` is the working name; naming was reopened on 2026-08-16 because the product is becoming cross-platform-capable technical-writing software rather than merely a MacDown rewrite | E17 public identity/appcast/release assets |
| O2 | Where does the app live long-term: rename this fork, or fresh repo? | E17 (can defer until final identity) |
| O3 | Import old MacDown prefs/themes on first run? (nice-to-have) | E13 |
| O4 | Which legacy themes ship in v1? → **PARTIALLY RESOLVED: Tomorrow Light + Tomorrow Dark shipped in E05**; more are data-only additions subject to E13/E07 design | E13/E07 |
| O5 | Final math rendering engine and exact delimiter compatibility | E19 architecture |
| O6 | Packaging/execution/licensing choices for Mermaid, D2, Graphviz and WaveDrom | E20/E21 architecture |

## 13. Appendix — D6: Contribution and extension design

**Old system (retired):** `MPPlugIn` loads NSBundle code **in-process** with a
`run:` selector, plus JavaScript injected into the preview WebView. In-process
arbitrary code loading is a stability/security dead end and is not carried over.

**New model, layered:**

1. **macOS 1.0 — First-party contribution seam (E14).** Internal
   `PreviewContribution` infrastructure, registry/lifecycle/isolation behaviour,
   TOC as a production contribution, plus deterministic test/proof contribution.
   E14 does not claim production math or Mermaid.
2. **macOS 1.0 — Text-filter commands (E14).** Executable scripts in
   `~/Library/Application Support/<App>/Commands/`; selected text/document →
   stdin, replacement ← stdout. Surfaced in menu + palette with explicit failure
   behaviour.
3. **macOS 1.0 — First-party technical content.** E19 uses the contribution
   model for math. E20 establishes a derived diagram renderer platform and ships
   Mermaid. E21 adds D2, Graphviz/DOT and WaveDrom only after E20 proves the
   common contract.
4. **Post-1.0 — JavaScriptCore extensions (evaluate).** Possible sandboxed hooks
   such as `onDidParse(ast)`, custom fenced-block renderers and commands. Design
   may be written in E14; third-party loading is not a macOS 1.0 requirement.
5. **Later — ExtensionKit out-of-process app extensions (evaluate only if
   needed).** Heavyweight; adopt only if real community demand justifies it.

The contribution layer is intentionally narrower than a generic plugin system.
First-party technical-content epics may extend it only when a concrete product
requirement demonstrates the need.

## 14. Post-1.0 iPad strategy

The iPad port is deliberately **not part of the macOS completion roadmap**.
The product should first prove that its document model, editor, preview, math,
diagrams, export and recovery behaviour form a complete Mac application.

After macOS 1.0 ships, future epics (E22+; exact numbering/scope defined then)
may cover:

1. identify which MacDownKit modules are genuinely platform-neutral and isolate
   AppKit-only adapters where required by a real iPad target;
2. build an iPad document/editor shell using the appropriate UIKit/SwiftUI
   document APIs and TextKit host;
3. bring preview, math, diagrams, themes and source navigation to iPad;
4. add iPad-specific file/workspace, multiwindow, keyboard and touch behaviour;
5. run an iPad-specific accessibility/performance/release pass.

Do not pre-build those layers during macOS work. The only current constraint is
to avoid needless AppKit dependencies in engine code when a platform-neutral
implementation is equally clear and no more abstract.
