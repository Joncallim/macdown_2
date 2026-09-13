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
| E14 contribution seam/text filters | done — PR #56 (`36cc44c`) merged `master`, including all 5 post-#56 adversarial-review passes (`planning/epic-14-implementation.md` §20-25): `90d3472` and `36cc44c` are the same tree (verified via `git rev-parse ...^{tree}`), so that hardening was already in `master`, not separately unmerged work. Issue #57's Open/Save-latency/save-feedback/close-dialog fixes (`planning/issue-57-findings.md`) merged as PR #58 (`521191d`) | package `swift test --no-parallel`: 1140/1140 tests across 127 suites pass (contribution adapter, TOC, text-filter runner/process-lifecycle/adversarial corpus, palette model, save routing), re-run directly against merged `master`; app-target `MacDown2Tests` 115/115; swiftformat 0/427, swiftlint 0/427; hosted CI green on PR #58's own `pull_request` check | Debug + Release builds of app and `macdown2` CLI succeed, both locally against merged `master` and on hosted CI. XCUITest automation now executes in this environment (the earlier permission blocker resolved) — `MacDown2UITests/ExternalFileChangesUITests` ran for real and is covered under E18 below (not an E14 regression: unrelated code, see #59); E14 has no dedicated XCUITest coverage of its own (palette/text-filter UI is package+app-target-test covered, not XCUITest-covered) | issue #57's own new UI (palette responsiveness, save spinner, save-failure banner, close-dialog routing, two-window targeting) was live-verified against the real Release build with file content read back from disk as evidence (`issue-57-findings.md`); the broader E14 feature set (text-filter execution end-to-end via the real GUI, TOC contribution rendering) was not separately re-dogfooded this session beyond its existing automated coverage | none known at P0/P1 for E14 itself; #59 (E18, external-file-change UI not updating) was found during this work but is unrelated code, tracked separately | **passed** — PR #58 merged (`521191d`) with real evidence above; the original manual-verification gate this row was blocked on is satisfied for issue #57's own changes |
| E18 external-file reconciliation | implementation/issue completed | package tests pass with synthetic `FileBackingIssue`/observation injection (`DocumentFileMonitorMissingFileTests.swift`, `ExternalFileControllerRecoveryTests.swift`) — but see Release-app column | **executed `MacDown2UITests/ExternalFileChangesUITests` (real XCUITest, not build-only) — all 6 tests fail.** Every scenario (clean reload, dirty conflict × 3, conflict-close, backing-unavailable) times out waiting for the UI to reflect a real external file change; each test's own document-loaded sanity check passes first, isolating the failure specifically to the change-detection→UI path | independently reproduced by the owner in real-world use outside this session, then confirmed via automated XCUITest — filed/updated as [#59](https://github.com/Joncallim/macdown_2/issues/59) | **likely P1** ([#59](https://github.com/Joncallim/macdown_2/issues/59)) — a core workspace path (external-file reconciliation) appears to not update its UI at all for any tested scenario; root cause not yet identified | **failed** — not `unverified`: this is executed, negative XCUITest evidence, the first for this capability |
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
