# Epic Index

Epics for the Swift/SwiftUI rewrite. See `../MIGRATION_PLAN.md` for the full plan, `../EPIC_STANDARD.md` for the mandatory Definition of Ready/architecture/slice/Definition of Done rules, and `../RELEASE_HARDENING.md` for cross-epic macOS 1.0 integration and release gates.

The live GitHub issue is the product contract. A current-master `planning/epic-NN-implementation.md` becomes the binding engineering contract only when the epic is ready to start. Implementation slices are execution contracts for workers; they must not require workers to invent architecture.

> **As-built note (amended at #28):** E02/E03 shipped with **native `NSWindow`
> tabs** — one window = one document, per-window sidebar — superseding the
> original single-window in-app tab bar design. Specs written before that
> change carry an "As built" amendment block; where an amendment conflicts
> with older spec text, the amendment wins.

## macOS 1.0 sequencing

The remaining feature sequence is intentionally:

`formats/export/settings → E14 contribution infrastructure → E19 math → E20 diagram platform + Mermaid → E21 renderer admission/integration → feature-complete gate + identity freeze → E15 whole-app polish/first-run → E16 localisation/string freeze → E17 migration/distribution`

E20 proves one diagram renderer and the shared rendering/caching/diagnostic/export architecture. E21 evaluates D2, Graphviz/DOT and WaveDrom individually; a candidate may be rejected for macOS 1.0 when licensing, security, bundle/runtime cost, maintenance or product value does not justify shipping it.

**No iPad implementation begins before macOS 1.0 is complete and released.** New engine code should avoid unnecessary AppKit coupling when a platform-neutral implementation is equally simple, but the Mac roadmap must not accumulate speculative portability abstractions or UIKit/iPad targets.

## Cross-epic release rules

`planning/RELEASE_HARDENING.md` does not add an epic. It binds the existing roadmap on matters that individual epics cannot safely own in isolation:

- first-party editing/preview/math/diagram/export remains local/offline and does not upload document content;
- E12 provides the export destination contract and E14 provides renderer-neutral derived content so Preview/Export do not diverge;
- text-filter commands have bounded execution/output and failure preserves source;
- the feature-complete gate freezes the public identity before E15/E16;
- one release-evidence ledger distinguishes implementation completion from real-app/release proof;
- critical XCUITests must actually execute on macOS 26 before 1.0;
- text round-trip fidelity is explicitly proven;
- E15 finalises first-run/in-app copy, E16 freezes/localises it, E17 must not invent new in-app UI after string freeze;
- E17 rehearses migration of representative real beta/development state into the release identity/update channel;
- no P0/P1 may remain for macOS 1.0.

## Epic table

| Epic | Title | Milestone/phase | Depends on | Status |
|------|-------|-----------------|------------|--------|
| E00 | Project foundations | M1 — Skeleton | — | ✅ done |
| E01 | File & format core | M1 — Skeleton | E00 | ✅ done |
| E02 | Workspace shell | M1 — Skeleton | E01 | ✅ done |
| E03 | Tab system | M1 — Skeleton | E01, E02 | ✅ done (native tabs) |
| E04 | EditorCore: NSTextView + TextKit 2 | M2 — Editor | E01 | ✅ done |
| E05 | Tree-sitter highlighting | M2 — Editor | E04 | ✅ done |
| E06 | Markdown engine | M3 — Markdown core | E01 | ✅ done (issue #7 closed completed) |
| E07 | Native preview (Textual) | M3 — Markdown core | E06, E04 | ✅ done (issue #8 closed completed; follow-up bugs tracked separately) |
| E08 | Content browser (document outline) | M3 — Markdown core | E06, E02 | ✅ done (issue #9 closed completed; follow-up issues tracked separately) |
| E09 | Folder browser | M4 — Workspace & formats | E01, E02, E03 | ✅ done |
| E10 | Editing assists | M2 — Editor | E04 | ✅ done (issue #11 closed completed; dogfood evidence remains part of release confidence) |
| E11 | Multi-format: JSON, HTML, LaTeX source + language registry | M4 — Workspace & formats | E05, E07 | ✅ done (issue #12; JSON tooling, HTML preview toggle, language registry completion. LaTeX/TeX source recognition from the amended scope was **not** implemented in this merge — tracked as a follow-up) |
| E12 | Export: HTML/PDF + shared derived-content destination | M4 — Workspace & formats | E06, E11 | ✅ done (issue #13, closed 2026-09-18). HTML export independently verified self-contained; derived-content contract proven by every later technical-content epic reusing it unmodified. A real, genuine `PDFExportAdapterTests` (E15 pass, 2026-09-19) drives the actual `WKWebView`→`NSPrintOperation`→`PDFKit` pipeline against a 25-section torture document and confirms real multi-page pagination with intact content — but is `.disabled` by default: it hung ~3328s then failed cleanly on retry, both times because `NSPrintOperation`'s child `WebContent` process cannot reach `launchservicesd`/`coreservicesd`/RunningBoard when hosted inside an `xcodebuild test`-driven run in this environment, the same class of gap CI already documents for `MacDown2UITests`. Not a product defect — the underlying pagination CSS/logic is presumably correct — but genuinely unverified by an automated run pending a suitable interactive-GUI test environment |
| E13 | Settings | M4 — Workspace & formats | E02 | ✅ done (issue #14; PR #52. Legacy-key migration map and full O3 import deferred to #53) |
| E14 | Renderer-neutral first-party contributions + text filters | M5 — feature completion | E07, E12 export contract | ✅ done (issue #15; PR #54 + E14B): contribution SPI/registry, `TOCContribution`, and Preview/Export integration (PR #54, with a 10-finding adversarial-review remediation), plus text-filter commands, Commands-menu/palette integration, and the post-1.0 extension-API design doc (E14B). On-device palette/text-filter keystroke journeys remain unverified pending manual confirmation — see `epic-14-implementation.md` §20 |
| E19 | First-class math and scientific notation | M5 — feature completion | E10, E12, E14 | ✅ done (issue #44, closed 2026-09-18; PR #61 + PR #62 merged, `e12ee9b`). The nested-code-fence adversarial case was run for real: Export's gap was found and fixed; Preview's analogous gap was found, characterized, and filed as [#63](https://github.com/Joncallim/macdown_2/issues/63) (P2, not fixed here — needs its own scoped design pass). Residual release-evidence debt: large-equation Release perf measurement **closed 2026-09-19** (E15 pass — `MathRenderingPerformanceTests`, 100 equations in 145ms against a 10s budget); live visual re-check of the post-#62 fixes remains, inside E15's own whole-app UI-test scope |
| E20 | Native diagram platform + Mermaid | M5 — feature completion | E12, E14 | ✅ done (issue #45, closed 2026-09-18; PRs #74-#78, #80). Real, non-mocked automated evidence throughout package and app-integration levels; UI-test execution and live visual dogfood remain open, blocked by this session's environment, tracked in `RELEASE_EVIDENCE.md`. One real, previously-undisclosed acceptance-criterion gap found while closing this issue — no interactive copy-as-SVG affordance exists for any diagram language — filed as [#86](https://github.com/Joncallim/macdown_2/issues/86) |
| E21 | Evaluate/integrate D2, Graphviz/DOT, WaveDrom | M5 — feature completion | E20 | ✅ done (issue #46, closed 2026-09-18; PRs #81-#85). D2 and Graphviz ACCEPTED, wired through Export + native Preview, adversarially hardened, and now have genuinely executed UI-test evidence (a first for this project's diagram epics — see `RELEASE_EVIDENCE.md`). WaveDrom DEFERRED, not rejected (disclosed `eval()`/CVE-2026-50733 finding, decision comment on #46). Two real, previously-undisclosed gaps found while closing this issue: no interactive copy-as-SVG affordance for any diagram language ([#86](https://github.com/Joncallim/macdown_2/issues/86)), and most of `MacDown2UITests` fails when actually executed, confirmed pre-existing ([#88](https://github.com/Joncallim/macdown_2/issues/88)) |
| Gate | macOS 1.0 feature-complete audit + public identity freeze | before E15 | all major feature epics through E21 | ✅ passed 2026-09-19. Identity frozen (`MacDown 2` / `com.joncallim.macdown2`); no P0/P1 found across all open issues; UI-test evidence substantially advanced (15/30 → 3/30 failing, PR #90). Full record in `RELEASE_EVIDENCE.md` |
| E15 | Liquid Glass + accessibility + whole-app audit + final first-run | M5 — polish & ship | frozen identity, E09, E19, E21 + feature-complete gate | ✅ accepted (2026-09-20) — issue #16, two explicit release prerequisites carried forward (final icon, final live VoiceOver/visual pass), not release-blocking for E16/E17. Real progress: #86 (copy-as-SVG) resolved, #70 (reload banner) resolved as a side effect of the #88 accessibility-identifier fix, #63 (nested-fence math corruption) fixed, E12/E19 inherited evidence debt closed (real PDF-pagination test, real math-rendering performance measurement), icon-only-button VoiceOver labels added, UI-test reliability substantially advanced (#88: 15/30 → 3/30 failing, precise root causes for the rest), text round-trip fidelity corpus executed (12 real file-write/read-back tests, no unexpected normalization found), and the app-had-no-icon gap closed with a functional placeholder (PR #99 — a code-generated icon at all 10 required sizes; explicitly not final design work, real artwork remains deliberately deferred). A live visual/accessibility dogfood pass was attempted again this session via `computer-use` (a different mechanism than prior attempts, per explicit owner direction): the app itself became grantable/enumerable for the first time, but window screen-capture failed outright (`audio/video capture failure`) and System Settings/VoiceOver Utility access was declined, so no screenshot or VoiceOver/Reduce Transparency/Increase Contrast/Reduce Motion evidence was obtained — recorded honestly in `RELEASE_EVIDENCE.md` rather than assumed. The whole-app 20-tab performance gap closed too (PR #101): a real, non-mocked test at 20-tab scale measured materializing 20 tabs at ~267 ms and re-visiting all 20 already-open tabs (a real tab switch) at ~0.02 ms, confirming the per-tab cache design genuinely delivers cheap switching rather than assuming it; landing it also surfaced and fixed a real cross-suite resource leak (20 un-released `EditorTextSystem`/highlighter graphs starving a different, pre-existing suite on CI). The first-run welcome screen closed too (PR #103): a first-launch-only window offering "Start Writing" or "Open a Sample Document" (a real tour of formatting/code/math/diagrams, seeded through the same document-update API a live edit uses), gated by a single preference bool rather than a new `AppSettings` domain field to avoid that domain's Codable-migration risk. Per explicit owner direction (2026-09-20), the two remaining blocked items now carry a settled disposition rather than pausing the mission: **the placeholder icon is a declared external release-asset dependency** ("⚠️ FINAL RELEASE ASSET REQUIRED" in `RELEASE_EVIDENCE.md`) — not a P0/P1, not a blocker for E16/E17, verified this pass that the asset catalog/build pipeline are correctly wired for a drop-in final icon (all 10 slots present, Release build genuinely consumes the catalog with zero `actool` warnings) — and **live screen-capture/VoiceOver attempts have stopped** (sufficiently demonstrated blocked) in favor of the strongest deterministic evidence obtainable without them: real render evidence for 15 app states via `ImageRenderer` (PR #105, CI-executed and passed, plus 5 outputs personally visually inspected via a standalone executable), a real `AXUIElement` menu-bar accessibility-tree walk (2373 elements, confirmed working via a permission distinct from screen capture, though per-window content AX is blocked by the same no-WindowServer-session root cause, independently reconfirmed via `NSRunningApplication.activate()` returning `false`), and a source-level accessibility audit (zero new defects found). Live VoiceOver and `MacDown2UITests`' real execution remain explicit, carried-forward manual/CI-environment prerequisites, not silently passed. The Liquid Glass/visual coherence code audit completed too: zero custom backgrounds behind system bars, zero glass-on-glass stacking (exactly 3 `Material` usages app-wide, each a single non-stacked overlay), sidebar/split-view fully native. E15 closure reconciliation then re-ran and reconciled the whole verification matrix (master's post-merge CI: package + full app-target test suites, lint/static checks, Debug/Release/CLI builds) — all green — and confirmed zero open P0/P1 issues. Closed with two explicit, carried-forward release prerequisites (final icon, final live VoiceOver/visual pass), neither a software defect nor a block on E16/E17. |
| E16 | Localization + in-app string freeze | M5 — polish & ship | final identity + final E15 in-app UI/copy | 🔶 in progress — issue #17. PR #108: added real `Localizable.xcstrings` String Catalog infrastructure to the app target (build-verified: `xcstringstool compile` runs on it, `xcodebuild build` succeeds). Used `xcodebuild -exportLocalizations` (Xcode's own genuine string-extraction tool, not manual guessing) to get an authoritative hardcoded-string audit: it flagged 32 real "non-literal key" locations where user-facing text bypasses automatic localization. Fixed the clear, mechanical cases and re-ran the same export to confirm the count actually dropped: 8 places where prose was broken into non-extractable `"..." + "..."` runtime concatenation, 4 menu items whose hand-built "✓ " checkmark prefix made the whole label non-extractable, 2 "Untitled"/"Untitled section" fallback literals hidden inside a ternary, roughly 20 raw AppKit `NSAlert`/`NSWindow.title` string assignments across 8 files (invisible to any localization pipeline regardless of the String Catalog, since they're plain `String` properties — including one manual plural ternary replaced with Foundation's automatic inflection syntax), and roughly 10 genuinely dynamic non-translatable values (diagram source, font names, filenames, technical IDs) explicitly marked `Text(verbatim:)` rather than left ambiguous. Result: 32 → 11 remaining findings, each individually reviewed as either an expected residual of an already-fixed pattern or documented follow-up. **Explicitly not attempted, and not faked**: actual translations into the 7 priority locales, a real Transifex project (needs the release owner's account/credentials — a genuine external dependency, not something a placeholder can stand in for), and pseudo-localization/layout QA. Not yet started: pluralisation verification in 3+ plural-rule languages, translation workflow documentation, string-freeze baseline record for E17 |
| E17 | Stateful migration, distribution & release | M5 — polish & ship | all macOS 1.0 work + E15/E16 | open |
| E18 | Live external-file changes | M4 — Workspace & formats | E01, E03 (as built), E04 | implementation present/issue closed; remaining evidence belongs in release ledger |

## Dependency summary

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

E18: E01 + E03(as built) + E04; document-safety evidence carried into release ledger

E19 + E21 + remaining Mac features
  ─▶ FEATURE-COMPLETE GATE + IDENTITY FREEZE
  ─▶ E15 (final in-app/first-run polish)
  ─▶ E16 (in-app string freeze)
  ─▶ E17 (state migration + signed/updateable macOS 1.0 release)
  ─▶ only then consider iPad epics
```

The exact critical path must be recalculated from live repository state when an epic architecture pass starts; the diagram above is roadmap ordering, not permission to ignore already-shipped dependencies or open regression/follow-up issues.

## Working rules

- Resolve work in dependency order unless the implementation architecture explicitly proves that parallel work is isolated.
- New/revised epics use the product-focused GitHub epic template, `../EPIC_STANDARD.md`, and applicable `../RELEASE_HARDENING.md` constraints.
- Each implementation architecture records its exact baseline SHA and reconciles the issue against live `master`, including relevant open follow-up bugs and newer cross-epic contracts.
- Older architecture work is not automatically binding after its product/release contract changes; it must be refreshed before implementation.
- Feature acceptance criteria require named evidence; package tests alone do not prove complete-app behaviour.
- Architecture/PR/commit prose must remain understandable without the originating agent conversation.
- Residual limitations become explicit follow-up issues or release-ledger entries rather than disappearing into handoff shorthand.
- The release gate records unknown/unavailable evidence as unverified, never inferred as passed.
