# Issue #17 / Epic 16 — Final localization and string freeze

## Owner summary

The final application must have consistent product naming, correctly resolved translated messages and usable layouts, not merely populated translation files. Preserve the existing catalog work, bring every later feature and diagnostic into it, verify an actual translation-service round trip, and freeze the exact string surface that distribution is allowed to package.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, reviewed 2026-09-24. This is downstream architecture. Do not modify catalogs while Claude is still implementing E22. Feature authors add their own strings with their implementation; this final pass starts only after the identity/E22/E23/#115 software-and-UI surface is stable. E17's application-side migration/updater/CLI/error UI must be implemented before the final freeze, even though its production distribution happens afterward. Any later in-app string change reopens the affected verification.

## Current implementation and evidence gaps

Read issue #17, epic-16-implementation.md, .tx/config and PseudoLocalizationLayoutTests. Existing app/package catalogs and fr/pl/ja seed translations are useful interim work. The historical ten-catalog list is not a final inventory: discover actual resources and targets, including newer EditorCore/presentation/Quick Look additions. .tx/config still uses placeholder organization/project slugs. A file-based XCSTRINGS configuration is not proof that any push/pull has succeeded.

The layout tests render real SwiftUI views but mostly assert that PNGs are nonblank. That does not prove correct translation, complete text, untruncated controls or native NSAlert/menu localization. SwiftUI's environment locale also does not automatically relocalize a String already resolved through Foundation/AppKit. Keep these tests as smoke coverage and add the missing semantic/runtime evidence.

## Ownership and inventory

Keep one catalog per resource-owning app/package/extension target with user-facing strings. Package callers explicitly use their resource bundle; the app uses the app bundle; Quick Look and the CLI use their own or shared packaged resource bundle as appropriate. Do not fix missing package strings by copying all entries into the app catalog. Verify resources: [.process("Resources")] and compiled localization bundles for every owning target.

Create a checked-in localization inventory/report schema: target, catalog path, bundle identity, source key, source/default text, interpolation signature, plural/device variants, translator comment, call sites, required locales and translation review status. Mark intentionally literal filenames, source text, user theme names, code, identifiers and engine syntax as non-translatable with a rationale. Do not indiscriminately localize authored document text or protocol/error codes.

Scan actual UI APIs as well as String(localized:): NSAlert fields/buttons, NSMenuItem titles, panel prompts, AppKit accessibility labels, enum/computed presentation strings, dynamic format errors, command descriptors, status messages, first-run content, theme/import validation, math/diagram diagnostics, recovery, Quick Look fallbacks, update UI and CLI human-readable errors. 'Open Folder' in NSFilePanelProvider is one baseline literal to include. A grep pass alone cannot prove completeness; compare extraction, static call-site audit and actual runtime key resolution.

Use the installed pinned Xcode extraction/compilation commands and record their version/help/output. The existing notes claim a lightweight xcstringstool extraction route and full-scheme SPM limitations; reverify the actual toolchain rather than blindly treating a historical command as universally supported. Run extraction into a disposable copy/worktree, review semantic differences and merge into owned catalogs without discarding translations/comments. Full-scheme export side effects must not mutate another worker's checkout. A tool hang is BLOCKED, not permission to call extraction complete.

## Interpolation, plurals and fallback

Preserve typed placeholder signatures and reordering semantics across all variants. Validate String.LocalizationValue versus SwiftUI LocalizedStringKey at the actual call site; do not assume integers use the same format specifier in both APIs. Reject missing/extra/wrong-type substitutions, invalid format strings and untranslated inflection markup. Resolve attributed inflection markup through the correct attributed localization API before converting it into a plain diagnostic String.

Keep fr/pl/ja as the three plural-rule test families unless the release locale policy explicitly changes. Exercise category boundaries with 0, 1, 2, 5, 11, 12, 14, 21, 22, 25, 101 and large counts; test fractional numbers only for messages whose arguments genuinely support fractions. Use current CLDR data as a fixture oracle and verify the actual macOS localized output. Do not hand-code plural selection in application code, or mistake a 'one' category for exactly integer 1 in every locale.

A catalog compiler pass proves format/schema validity, not native linguistic correctness. Native-speaker review of the seeded release translations is an explicit prerequisite; record reviewer, reviewed catalog/source digest, critical terminology decisions and unresolved findings. AI-generated or maintainer-seeded strings stay labelled as drafts until that review exists. At least one shipped non-English locale must cover every critical app journey; preserve the existing fr/pl/ja quality obligation rather than declaring it passed from structure alone.

Keep priority ja/zh-Hans/zh-Hant/de/fr/es/ko-KR in the contributor roadmap without advertising unverified languages as complete. Reconcile platform locale aliases such as Korean variants with actual compiled bundle lookup and Transifex language mapping; never silently rename keys because two display labels look similar.

Fallback policy: English is the explicit development fallback. Absent noncritical translations may fall back deliberately; no critical destructive/recovery/import/update message in a claimed production locale may silently remain untranslated. Partial locales stay outside the advertised fully supported set and, where necessary, out of production localization packaging until accepted. Unknown user theme names and filenames remain verbatim. A missing translation cannot display a raw catalog key, placeholder or inflection expression.

## Safe Transifex synchronization

Use file-based XCSTRINGS resources, not the unrelated Transifex Native runtime SDK. No translation network service is added to the shipping app. Replace placeholder slugs only with verified account/project/resource identifiers. Credentials remain in the operator's authorized secret store/environment, never .tx/config, command history examples, artifacts or commits. Account availability is an execution prerequisite, not something this hand-off claims to have configured.

Define Git's English source catalog as the source-string authority and the reviewed Transifex project as the translation collaboration authority. Before pushing, export only the intended source delta in a staging checkout. Before pulling, capture source key/text/comment/substitution digests. Pull into staging, structurally compare every catalog, preserve source and existing non-target metadata, compile and test, then submit the reviewed change. A downloaded file is never committed 'exactly as pulled' without validation.

The current Transifex XCSTRINGS documentation states that source uploads can update embedded translations too and that a returned catalog may include all languages. It also documents normalization of single-plural languages. Therefore prove a non-destructive canary round trip with ordinary text, reordered placeholders, one plural substitution, a non-translatable entry and a Japanese single-form message. Reject accidental source/other-language deletion or overwriting reviewed translations with stale seed values. Preserve semantic equivalence rather than demanding byte-identical JSON key ordering or plural serialization.

Document exact installed CLI version, verified tx push/pull flags, expected resource identifiers, staging/validation/rollback steps and who owns review. Do not rely on a percentage-complete flag as proof all critical translations are reviewed: compare the returned critical-key inventory and review metadata. Preserve the pre-sync snapshot so an unwanted remote/local update can be reconciled without loss. The workflow must be runnable from repository documentation without chat context.

## Layout and real locale verification

Extend the existing smoke tests with full pseudo-localized expansion, accented text and a right-to-left stress locale for layout testing. Preserve format placeholders when generating pseudo text. Stress narrow supported windows, long filenames, errors, menus, sheets, Appearance samples, multi-line progress, command palette, E22 status/gutter controls, first-run/import/update UI and Quick Look fallback messages.

Assertions include expected localized sentinel/key values from each resource bundle, minimum meaningful control bounds, actionable button visibility, no overlap/scroll-inaccessible controls, and appropriate text wrapping. Nonblank image checks remain supplementary. Explicitly force locale for pre-resolved Foundation messages in unit tests; test the actual process language at launch for native menus/panels/sheets. Do not mutate the owner's persistent AppleLanguages setting. Use #88's isolated account/launch configuration and restore its state afterward.

Run complete critical journeys in at least one QA-approved non-English locale on the final app, with real NSAlert, save/export panels, conflict/recovery, theme import and Quick Look. Capture screenshots and native-speaker observations tied to an exact build. Verify VoiceOver labels, reading order and keyboard reachability; localized labels must not become test identifiers. Retain stable accessibility identifiers separately from displayed text.

## Freeze artifact and dependency gate

Write a machine-readable string-freeze record containing product identity, source SHA, per-catalog source/translation digest, resource-bundle inventory, supported locale list, review evidence IDs, plural/runtime/layout results and the exact UI/source baseline. Keep historical records immutable. A verification script computes semantic source-surface changes and fails the release preflight if the baseline differs without new verification.

The software/UI stabilization subgate of #115 precedes this pass; its final whole-app/release authorization consumes E16's resulting evidence. This distinction must be recorded in the #115/E17 execution plan, not handled through a hidden waiver or by calling an interim catalog set 'final'. E17 may later change website/README/release-note copy outside the app. Packaging metadata that changes displayed app identity or new updater/migration strings still requires localization revalidation.

## Implementation sequence and completion

1. Reconcile final target/catalog/identity inventory and remove stale extraction/configuration assumptions. Add structural coverage, interpolation and critical-key validation tests.
2. Extract/merge every final feature string; resolve placeholder issues and compile all intended locales.
3. Configure and verify the staged Transifex canary round trip, then synchronize the real source/translation delta safely.
4. Complete native-speaker review, three-family plural/runtime checks, pseudo-layout and one complete shipped non-English UI journey through #88.
5. Freeze the exact baseline, add the release preflight check and update E16/#115 evidence. Do not declare completion while review/access credentials or critical GUI checks are missing.

Allowed files: owned catalogs/resource declarations, localization-specific call-site repairs, .tx/config after real identifiers are known, test/script/evidence docs and the narrow layout fixes demonstrated by QA. No E22 feature redesign, no arbitrary translation-service runtime, no moving package strings into the wrong bundle.

Self-review addressed nonblank snapshots as false layout proof, process versus SwiftUI locale, absent bundle resources, stale hardcoded catalog counts, overwriting translated catalogs during source upload, single-plural normalization, source/default-value fallbacks and late E17 strings invalidating the freeze. No translation quality, Transifex execution or native GUI pass is asserted by this architecture.

Primary references: https://help.transifex.com/en/articles/9459174-xcode-strings-catalogs-xcstrings ; https://developers.transifex.com/docs/cli ; https://cldr.unicode.org/index/cldr-spec/plural-rules .
