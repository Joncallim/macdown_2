# Issue #115 — Finite debt closure and exact-artifact proof

## Owner summary

Close existing promises, verify the actual finished application and produce an auditable go/no-go for one exact artifact. This is an evidence/hardening gate, not another feature epic or a repeated historical-debt hunt. Architecture coverage, merged PRs and green package tests are not release authorization.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md), [readiness review](READINESS_REVIEW.md), readiness.json and [canonical release sequence](../RELEASE_SEQUENCE.md). Claude retains all current E22 implementation ownership. This document closes no issue and supplies no runtime PASS.

## Reconciled authority and finite scope

The historical debt search was already completed through PR #122; PR #114's as-built reconciliation is merged. Preserve its conclusions unless a new concrete defect disproves one. Do not resurrect resolved #34/#36/#37, #62/#63 or old evidence waivers without reading their actual current disposition.

The implementation closure set is #53, #79, #88, #112/E22, #113/E23 and #116–#121. #17/E16 and #18/E17 provide final language/distribution proof. Full TeX compilation, generic plugins/marketplaces, visual diagram authoring, interactive Mermaid click features and iPad remain non-goals. WaveDrom remains rejected for 1.0 under its original optional-renderer contract; rejection cannot be reused to waive required features.

## Non-circular sequence

The staged canonical RELEASE_SEQUENCE.md supplies explicit S/V/P semantics and overrides the old linear shorthand when this PR is adopted. It preserves all acceptance requirements:

**S — software/UI stabilized.** E22/E23 and required product fixes, plus E17's bootstrap/migration/CLI/updater application code and strings, are implemented and engineering-verified. #115 stays OPEN. This milestone—not final issue closure—is E16's prerequisite.

**V — final localization and private proof.** E16 freezes the final string/UI/resource surface. E17 creates private unapproved signed/notarized candidates and controlled update rehearsals. #88 and the gate exercise exact immutable bytes. This is evidence preparation, not a public RC or production authorization. Missing Mac access, credentials, native review or other required proof keeps V incomplete.

**P — authorized public promotion.** Only once every required obligation and final E16 record passes may #115 close and public release be separately authorized. Promote the SAME V artifact; no rebuild/re-sign afterwards. Changed bytes/identity/entitlements/resources invalidate affected proof. No author can describe a private candidate as authorized merely because its build succeeded.

Issue bodies and historical ledger rows may retain their original wording. At adoption, add concise links identifying S versus final closure where required; do not rewrite historical results, modify E22's active plan or mark checkboxes automatically. Repository hardening contract is the cross-epic authority. No required GUI/security/manual test is removed to resolve the loop.

## Evidence model

Create a versioned current obligation manifest with stable IDs, original epic/issue paragraph, precise behavior, owner, evidence kinds, source/contract baseline, severity, applicability and references. Preserve historical records separately. During execution NOT_RUN/RUNNING/BLOCKED/FAIL are truthful states, but none permits final closure. Final required dispositions are FIXED with passing evidence, PROVED with passing evidence, or REJECTED_FOR_1_0 only for originally optional candidates.

Each evidence record identifies actual run, source/test-driver SHA, app path/tree/hash/CDHash, nested executable identities, OS/SDK/toolchain/hardware, fixtures, selected/discovered/executed/failed/skipped tests and retained result/log/output artifacts. Manual observations include the actual reviewer and reviewed artifact. Hashes establish identity, not proof that an assertion ran; inspect result contents and counts. No expired /tmp pointer or 'tested locally' statement suffices. Preserve failed/superseded attempts and redact unrelated personal data/secrets.

A superseded old test needs its exact behavior and a named stronger current proof; SUPERSEDED is a relationship, not a fourth waiver disposition. A deleted/renamed test cannot reduce required behavior silently. Do not grep preserved historical words such as unverified and confuse them with current manifest status; equally, do not delete them to make a gate green.

## Required coverage

| Family | Required ownership and evidence |
| --- | --- |
| E00–E04 foundations/document/native-tab/editor | Current real open/edit/save/restore, encoding/source fidelity, selection/lifetime and recovery. Preserve audited resolved architecture; no obsolete single-window assumption. |
| E05 highlighting/chrome/themes | E22's real Release hot/full paths and synchronous main-actor budgets; E23's semantic roles/eight themes/custom themes. A best-of-five microbenchmark is best-case evidence, not p95 or whole-app latency. |
| E06–E09 parse/Preview/outline/FileTree | Map all applicable historical manual/Release rows to current evidence, including links/images/selection and smaller FileTree app-layer paths. |
| E10/E11 source editing/TeX | E22's multi-selection/language/fence mechanics, actual TeX recognition/highlighter-or-approved-fallback and real byte-preserving round trips; no Markdown Preview for TeX. |
| E12 export/PDF | #118/#121/#88: real menu/save-panel HTML/PDF, genuine pagination/searchable text, parity, final-byte/memory limits, contained reads, asset crash recovery and cancellation. PR #114's as-built work is historical completed work, not new scope. |
| E13 settings | #53 compatible old schemas/import; E22 real parser capability; E23 theme catalog and live apply. Older EditorSettings cannot silently become whole-domain defaults. |
| E14 contributions/palette/filters | #117 anchors/destinations/snapshot and E22 registry. Actual built-in/discovered filter, selection/undo, failure/timeout/cancel/close/supersession/multi-window journeys. |
| E15 identity/accessibility | Final approved artwork and actual Finder/Dock/small-size presentation; keyboard/VoiceOver/light/dark/Increase Contrast/Reduce Transparency/Reduce Motion/resizing across all completed UI. |
| E18 external changes | #119/#120/#88: clean/dirty/own-save, newest disk conflict choices, move/delete, native close sheet, recovery and view-state behavior; real 1/10 MiB timings and bounded watcher/probe lifetime. |
| E19 math | All SIX #116 areas, including pre-parse escape/currency grammar, structured diagnostics, accessible attachments and own-span source identity; actual post-#62 visual/export sizing and 100-equation performance. |
| E20/E21 diagrams | #79/E23 all three engines, structured palette/opaque canvas, actual defaults/print legibility, offline containment, output/queue/memory/cancellation calibration. Internal D2 WASM exception never permits active Quick Look output. |
| HTML Preview isolation | #121's immutable root/load ownership, actual constrained opened-object races, MIME/CSP/network/teardown and resource accounting. |
| E16/E17 final product | Native-reviewed language/plurals/layout and exact freeze; real CLI/open/stdin/wait; legacy and development-state migration including themes/snippets; clean Gatekeeper and signed N -> N+1 update preserving state. |

Expand these into individual obligations; one green issue number is not evidence for its constituent behaviors. All still-applicable manual/Release/XCUITest rows from closed epics remain accounted for. New defect work stays focused under an existing owner where possible, not speculative backlog growth.

## Fresh orthogonal reviews

At stabilized source, run separately scoped reviews of: data/recovery/lifetimes and asynchronous publication; resource/security/HTML/renderer/Quick Look/filter/CLI/update boundaries; behavioral integration/Unicode/encoding/commands and actual FileTree/Preview/JSONSupport glue; Release performance/cold starts/retained workers/descriptors/cache bytes; and evidence/UX/accessibility/localization/public claims.

Review actual source and tests, not summaries of old bots. Explicitly cover the less-reviewed FileTree app layer, CLI and smaller Preview/JSONSupport code plus every E22/E23/#116–#121 change. Record provenance, inspected scope, concrete reproductions, severity, tests and fixes. Multiple lenses in one session are self-review passes, not independent reviewers. Separate actual executions/readers are required before claiming independence.

Service quota exhaustion is external unavailability, not a code finding or a successful review. Use another already-authorized viable review route where permitted, with truthful provenance. Do not repeatedly request an exhausted bot, buy services, weaken required checks or describe self-review as independent. A mandatory unavailable review blocks its unit/merge, not unrelated independent preparation.

Re-review changed invariants after fixes and keep every failed run. Timing reruns may diagnose noise, but minimum/median/p95/cold/whole-path measures must retain distinct meanings and original threshold semantics. No repeated rerun-until-green, skipped native test or weakened assertion can clear an obligation.

## Validator and execution

Implement an offline validator for schema/coverage/links/digests/artifact identity plus independently retained actual results. Reject missing/duplicate obligations, unsupported rejection, stale source/string/artifact identity, unresolved critical failures/skips and release-relevant P0/P1/P2. Cosmetic P3 requires explicit owner acceptance and cannot conceal functional/data/security impact. A separate read-only live-repository check confirms current blockers/ref before authorization; unavailable access yields BLOCKED.

The validator never closes issues, manufactures pass results or publishes. The architecture readiness.json in this PR is a UNIT DEPENDENCY plan only, not the future runtime release-evidence manifest. Passing its static graph tests cannot pass #115 or any application test.

At S execute required engineering suites/Release measurements and applicable interactive work. At V use #88's exact-artifact procedure with actual Mac permissions and public UI, VoiceOver, HTML/PDF independent inspection, themes/math/diagrams, Finder/Quick Look, first run/import/update and at least one accepted non-English locale. Verify actual app/CLI/extension executable paths so a nearby Debug build cannot masquerade as the candidate.

Run real stateful migration and two signed-build update rehearsals via #18. Every product fix invalidates affected binary/string evidence and requires a new identified candidate plus affected checks and final critical regression. Never sign new bytes after manual proof and copy the old approval over them.

## Units and completion

A. Adopt explicit sequencing documentation, inventory finite obligations and implement evidence-validator/test infrastructure without touching E22.
B. Consume tested owner implementation units; perform fresh scoped review and resolve concrete defects; establish S only after all release-app strings exist.
C. Complete E16, build private V artifacts and execute the full evidence matrix. #115 remains open while anything required is missing.
D. Validate actual results, live blockers and exact identity; close #115 only on a genuine pass. P is separately authorized and not an automatic side effect of documentation/CI.

Allowed changes are release-contract/evidence/validation documents and scripts; production fixes remain their owner PRs. Stop on lost data, wrong artifact, missing proof, contradictory authority, unauthorized budget relaxation or public publication before P.

Second review resolves the issue-closure/freeze loop, distinguishes structural plan validation from actual release evidence, preserves benchmark meaning and names genuine review-service failure behavior. No full source audit, independent review or native execution is claimed to have happened merely because this architecture was reviewed. Final outcome is GO for one proved artifact or NO-GO with exact remaining obligations, never 'ready except for manual testing'.
