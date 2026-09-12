# macOS 1.0 release-evidence ledger

> Status: **scaffold until the feature-complete gate**
>
> This is not another epic and it is not a substitute for individual epic test records. It is the owner-readable cross-product ledger required by `planning/RELEASE_HARDENING.md` so a closed issue is never mistaken for proof that the exact release application has been validated end-to-end.

## Rules

- `implemented` means the intended code/product work exists; it does **not** mean release-proven.
- Automated package/unit evidence, real-app Release evidence and manual evidence are tracked separately.
- `build-for-testing` does not count as executed XCUITest evidence.
- Unknown/unavailable evidence is written `unverified`, never inferred as passed.
- P0/P1 block macOS 1.0. P2 requires explicit owner-readable acceptance or a fix. P3 may defer with a record.
- This ledger is refreshed from current `master` at the feature-complete gate and again on the exact E17 release candidate.

## Evidence columns

| Field | Meaning |
|---|---|
| Implementation | `done`, `open`, or a concise current state |
| Automated evidence | package/unit/integration/CI evidence relevant to the capability |
| Release-app evidence | evidence from the real app in Release configuration, including executed XCUITests where required |
| Manual evidence | recorded dogfood/recovery/accessibility/fidelity journey where required |
| Open P0/P1/P2 | unresolved release-relevant findings; link issue(s) rather than hiding them in prose |
| Release status | `unverified`, `blocked`, `accepted`, or `passed` with short reason |

## Initial roadmap scaffold

This initial table is deliberately conservative. It captures implementation status known from the roadmap while leaving release proof unverified until evidence is reconciled at the gate.

| Capability / epic | Implementation | Automated evidence | Release-app evidence | Manual evidence | Open P0/P1/P2 | Release status |
|---|---|---|---|---|---|---|
| E00 foundations | done | reconcile existing records | unverified | unverified | reconcile | unverified |
| E01 file/format core | done | reconcile existing records | unverified | unverified | reconcile | unverified |
| E02 workspace shell | done | reconcile existing records | unverified | unverified | reconcile | unverified |
| E03 native tabs/session restore | done | reconcile existing records | unverified | unverified | reconcile | unverified |
| E04 TextKit editor | done | reconcile existing perf/tests | unverified | unverified | reconcile | unverified |
| E05 highlighting/themes | done | reconcile existing perf/tests | unverified | unverified | reconcile | unverified |
| E06 Markdown engine | done | reconcile issue/PR evidence | unverified | unverified | reconcile | unverified |
| E07 native preview/scroll sync | done | reconcile issue/PR evidence | unverified | unverified | reconcile | unverified |
| E08 content outline | done | reconcile issue/PR evidence | unverified | unverified | reconcile live follow-ups | unverified |
| E09 folder browser | done | existing package/Release benchmark records exist; reconcile exact gate | unverified | unverified | reconcile | unverified |
| E10 editing assists | done | substantial package/UI smoke evidence exists | Release dogfood must be reconciled | manual Release matrix previously remained a confidence gate | reconcile | unverified |
| E11 multi-format/TeX source | open | — | — | — | architecture refresh required (#43) | blocked until implemented |
| E12 export/shared destination | done | 53 ExportService package tests pass: cmark lifecycle, composer, resources/URL policy, file writer, derived-content fallback, fidelity corpus, offline/no-hosted-renderer | unverified — Release build passes; no executed UI test of Export… | unverified — PDF pagination and Export… menu need Release dogfood | none known; residual risks recorded in `epic-12-implementation.md` §18 | unverified — package evidence only |
| E13 settings | open | — | — | — | — | blocked until implemented |
| E14 contribution seam/text filters | done — PR #56 (`36cc44c`) merged `master`; substantial post-merge hardening (5 further adversarial-review passes, `planning/epic-14-implementation.md` §20-25) and issue #57's Open/Save-latency/save-feedback/close-dialog fixes (`planning/issue-57-findings.md`) committed on `epic/14-text-filters`, not yet merged | package `swift test --no-parallel`: 1140/1140 tests across 127 suites pass (contribution adapter, TOC, text-filter runner/process-lifecycle/adversarial corpus, palette model, save routing); app-target `MacDown2Tests` 115/115; swiftformat 0/427, swiftlint 0/427 | Debug + Release builds of app and `macdown2` CLI succeed; **no executed XCUITest** — `xcodebuild test` against `MacDown2UITests` failed with "Timed out while enabling automation mode" in this environment (no Automation/Accessibility permission available) | **unverified** — the manual UI/dogfood matrix (palette responsiveness, save spinner, save-failure banner, close-dialog after a deleted backing file, two-window save targeting) has never been driven by an interactive session; explicitly not inferred passing (see `epic-14-implementation.md` §24 and `issue-57-findings.md`'s "Outstanding gate") | none known at P0/P1; acceptance criteria for issue #15 appear met by evidence above but the issue is deliberately left open pending the manual gate | **blocked on manual/Release-app verification** — implementation and automated evidence are done; do not infer the release-blocking manual gate as passed |
| E18 external-file reconciliation | implementation/issue completed | reconcile package/app records | hosted/real-app evidence must be reconciled | sustained dogfood evidence previously remained a publication gate | reconcile | unverified |
| E19 math | open | — | — | — | — | blocked until implemented |
| E20 Mermaid diagram platform | open | — | — | — | — | blocked until implemented |
| E21 candidate engineering renderers | open | — | — | — | each candidate accept/reject decision required | blocked until evaluated |
| Text round-trip fidelity corpus | gate work | — | unverified | unverified | — | unverified |
| Critical XCUITest execution | gate work | build-only evidence is insufficient | unverified | local-Mac run acceptable if hosted unavailable | — | unverified |
| Public identity freeze/migration map | gate work | — | — | owner decision required | — | unverified |
| E15 whole-app polish/first-run | open | — | — | — | — | blocked until gate |
| E16 localisation/string freeze | open | — | — | — | — | blocked until E15 |
| E17 signed/stateful update release | open | — | — | — | — | blocked until E15/E16 |

## Feature-complete gate checklist

Before E15 begins, this ledger must show:

- [ ] final public identity and development→release namespace migration plan frozen;
- [ ] every planned macOS 1.0 feature through E21 implemented or, for E21 candidates, explicitly accepted/rejected;
- [ ] previous epic evidence debt reconciled rather than silently waived;
- [ ] critical XCUITests actually executed on macOS 26 or explicitly `unverified`/blocking;
- [ ] text round-trip fidelity corpus executed;
- [ ] complete-product Release performance/memory evidence recorded where required;
- [ ] document-safety/recovery/external-change flows manually/automatically exercised;
- [ ] no P0/P1 remains; accepted P2s are recorded with rationale;
- [ ] first-run/in-app UI scope is stable enough for E15/E16 finalisation.

## E17 release-candidate refresh

On the exact release candidate, refresh this ledger again and add evidence for:

- clean signed/notarised install;
- stateful development/beta identity migration;
- repeated/idempotent migration/relaunch;
- Sparkle RC N → RC N+1 with representative state preserved;
- final CLI behaviour;
- E16 string-freeze compliance;
- final README/release/capability claims matching proven evidence.

The release candidate is not approved while any P0/P1 or required `unverified` gate remains.
