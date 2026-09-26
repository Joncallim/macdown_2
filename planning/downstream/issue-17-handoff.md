# Issue #17 / E16 — Final localization and immutable string freeze

## Owner summary

Ship correctly resolved messages and usable translated layouts, not merely populated String Catalogs. Preserve the current catalog work, include every completed feature/release-app string, verify translation exchange and freeze the exact source/translation surface consumed by release verification.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md), [readiness review](READINESS_REVIEW.md) and [release sequence](../RELEASE_SEQUENCE.md). E22 remains active and owns its current catalog deltas. The final E16 pass begins after milestone S (software/UI stabilized), NOT after #115's final issue closure, which itself requires E16/exact-artifact proof. #115 stays open until V is proven. This is sequencing clarification, not a waived test.

## Current source reconciliation

The original E16 infrastructure/seed translations remain historical interim evidence. The ten-catalog list is already stale: E22 introduced EditorCore Resources/Localizable.xcstrings and future presentation/Quick Look targets add their own resources. Discover actual target/call-site/catalog ownership at the final baseline. Do not copy the old count or declare fr/pl/ja seed text professionally reviewed.

.tx/config has placeholder organization/project identifiers. Existing PseudoLocalizationLayoutTests mostly assert nonblank real-view PNGs. Such tests do not prove a localized sentinel resolved, every control is visible, AppKit menus/sheets use the correct language or a native speaker reviewed it. SwiftUI's environment locale does not relocalize Strings already resolved by Foundation outside that view.

MostlyText is settled. Include actual final product identifiers and approved artwork labels from their owning decisions, not stale MacDown 2 display text or guessed domain values. Proper product/theme names are not automatically translated; obsolete public identity in real UI still requires correction.

## Catalog ownership and audit

Keep each string in its actual app/package/extension/CLI resource bundle. Package callers must resolve through Bundle.module where applicable and targets declare processed resources. Do not repair missing package lookup by duplicating all keys into the main app catalog. Test each compiled resource bundle independently, including cold Quick Look without app launch.

Maintain a machine-readable inventory: target/catalog/bundle, source key/default value, interpolation signature, variants, translator comment/call site, required locales and review state. Distinguish intentionally literal authored text, filenames, user theme names, code/protocol identifiers and engine syntax. Never localize document source or stable machine diagnostic codes.

Audit Foundation/SwiftUI and raw AppKit call sites: NSAlert/button/menu/panel/accessibility strings, computed enum labels, dynamic format/recovery errors, palette commands, E22 status/find controls, math/diagrams, custom themes/import, first run, updater/bootstrap/CLI and Quick Look fallbacks. Extraction plus static call-site audit plus actual runtime sentinels is required; grep alone is not proof.

Run pinned installed-Xcode extraction/compilation commands, recording their actual help/version/results. Historical xcstringstool/xcodebuild export claims must be reverified on the shipping toolchain. Extract into an isolated staging checkout, review semantic deltas, preserve translations/comments/variants and merge only intended owned resources. Full-scheme side effects cannot mutate another worker's checkout. Tool failure/hang is blocked evidence, not a completed audit.

## Interpolation, plurals and fallback

Validate placeholder count/type/reordering across every locale/variant against the actual call site's interpolation API. String.LocalizationValue and SwiftUI LocalizedStringKey cannot be assumed to use identical specifiers. Reject invalid formats, missing/extra placeholders or unresolved inflection markup. Resolve attributed inflection through the correct attributed API before turning it into a plain diagnostic String.

Retain fr/pl/ja as the established three plural-family verification locales unless the owner explicitly changes the release locale policy. Test applicable integer boundaries 0,1,2,5,11,12,14,21,22,25,101 and large counts; decimals only where the real message supports them. Use current CLDR and actual platform output rather than handwritten plural selection in app code. Catalog compilation validates structure, not linguistic correctness.

Required seeded-release native-speaker review records reviewer, source/catalog digest, terminology decisions and unresolved findings. AI/maintainer draft translations stay drafts until that review occurs. At least one shipped non-English locale must cover all critical journeys without blocking untranslated/clipped UI. Do not drop an existing native-review obligation merely because one locale's smoke test rendered.

English remains development fallback. Partial/unreviewed locales are not advertised as complete and cannot silently ship untranslated destructive/recovery/import/update actions in a claimed supported language. No raw key, printf token or inflection expression reaches UI. Reconcile actual bundle/Transifex locale aliases, including Korean variants, without renaming tags by guess. Other priority locales remain contributor work, not invented completed coverage.

## Safe Transifex workflow

Use file-based XCSTRINGS resources, not a network runtime inside the app. Replace placeholders only with verified authorized project/resource identifiers. Discover/use available authorized account tooling before claiming account work cannot be automated, but never invent credentials, purchase service or publish source translations to an unrelated project. Keep tokens out of repository, command arguments/history examples and evidence.

Git owns source strings; the reviewed collaboration project owns accepted translation exchange. Stage source pushes and translation pulls in a disposable checkout. Snapshot source key/text/comment/substitution digests before synchronization. Validate the entire returned catalog, retaining non-target translations and metadata; do not commit exactly-as-pulled blindly. A source upload may carry embedded translations, so stale seeds must not overwrite reviewed remote text.

The first real round trip is a canary containing ordinary text, reordered placeholders, a plural substitution, a deliberately non-translatable entry and Japanese single-form output. Compare semantic content, not JSON key order or equivalent single-plural serialization. Reject unintended language/source deletion, altered placeholders or lost review state. Only then synchronize production resources. Keep pre-sync copies for non-destructive recovery.

Record actual CLI/API version, verified commands, project identifiers, staging/compile/runtime validation and rollback/review ownership. Percentage translated is not a substitute for critical-key and review completeness. Missing authorized project access is a bounded external prerequisite; local inventory/compilation/QA preparation can continue.

## Runtime and layout evidence

Keep existing nonblank-render smoke tests but add exact localized sentinel assertions in EVERY resource-owning bundle and relevant interpolation/diagnostic path. Use explicit locale for pre-resolved Foundation values in unit tests. Real AppKit menu/panel/sheet language is tested through process launch under #88's isolated account/configuration, not by mutating the owner's global AppleLanguages.

Pseudo-localization expands and accents real strings while preserving placeholders; include right-to-left stress layout even when not a shipped locale. Test narrow supported windows, long filenames, menus/sheets, Appearance samples, palette/find/status controls, progress/errors, conflict/recovery, migration/updater, first run and Quick Look. Assert control visibility, meaningful bounds, reachability, wrapping, overlap and scroll access—not just nonblank pixels. Keep accessibility identifiers stable and distinct from translated labels.

Run a complete critical journey in a QA-approved shipped non-English language on the final application with actual native controls. Capture screenshots and named observations tied to the build, including keyboard/VoiceOver labels/reading order. Language review is not a software property a static test can fabricate; unresolved human QA remains explicit.

## Freeze record and changed-source handling

Freeze exact product identity, source SHA, per-catalog source/translation semantic hashes, resource inventory, supported locales, review IDs, interpolation/plural/runtime/layout evidence and the UI baseline. Keep prior records immutable. A validation script rejects release packaging when any relevant source/string/resource identity changes without affected reverification.

All #53/#18 application-side migration/update/CLI text must land before S; E17 is not allowed to introduce an English-only screen later. Non-app README/website/release notes may change independently, but displayed app identity, package/extension UI or error strings reopen the affected freeze. A fix during V creates a new candidate and updates affected localization/GUI evidence; do not call newly signed bytes the old tested artifact.

## Units, tests and completion

A. Final resource/identity inventory, structural coverage/interpolation tests and extraction reconciliation after S.
B. Complete all feature string deltas and compile intended locales; retain exact runtime sentinel tests.
C. Authorized staged Transifex canary and synchronization, with actual project identifiers.
D. Native-speaker review, three-family plural verification, pseudo-layout and complete non-English public-UI evidence via #88.
E. Freeze record and release preflight validation consumed by V/#115.

Allowed changes: owned catalogs/resource declarations, localization-specific call-site/layout corrections, verified .tx config and QA scripts/evidence. No E22 feature redesign, document translation, wrong-bundle duplication or new runtime translation service. Run serial format/lint/build/tests as applicable plus actual interactive language QA. Stop on unknown resource ownership, lost translations, malformed placeholders, unapproved source changes or missing required native review.

Second review removes the issue-closure/string-freeze cycle and fixed catalog-count assumptions while retaining the original native QA, safe translation-exchange and runtime requirements. No catalog compilation, translation service exchange, human review or GUI execution is claimed by this architecture pass.
