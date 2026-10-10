# File-safety closure register

Finite register for the file-safety and release-convergence handoff of 10 October 2026. It records, per obligation, what is proved, by which immutable evidence, and what is still missing. It is not an epic and does not replace the owner issues; it must be updated in the PR that changes an obligation's status. A shared predicate, a closed issue, a test count or a similar-looking passing test is not evidence for an obligation here.

Baseline when written: `master` after #396 (source tree with the regressions below merged). Evidence is **CI-green PRs plus local runs**; no signed candidate, native UI run (`MacDown2UITests`), native Quick Look/WebKit corroboration or consecutive-suite reproducibility run has been executed for this register yet. A local full serial package run on a heavily loaded machine (load ≈ 24) failed 41 wall-clock-sensitive tests (WebKit, subprocess, 2–5 s bounds) outside the areas below; it is not accepted evidence and the runs must be repeated on an idle machine.

Status: **PROVED** (production-path regression at the required layer, discrimination shown), **PARTIAL** (some scenarios proved; gap named), **OPEN** (not started or no proof), **BLOCKED** (needs an environment/authority not available).

## Named regressions

| ID | Owner | Invariant | Evidence | Status | Missing |
| --- | --- | --- | --- | --- | --- |
| R1 | #183 F01 / #375 | An obsolete disk snapshot (Use Disk Version / Reopen) cannot replace newer text or another document | `UseDiskVersionRaceTests` (edit during recovery cleanup; non-superseded reload still lands) | PARTIAL | Native tab-switch, Save As/lifetime change and disposal during the held cleanup; surviving recovery bytes after each |
| R2 | #183 F01 / #376 | Recovery retry / Save As continuation cannot publish or acknowledge over a live lifetime | `WorkspaceRecoveryRetryRaceTests` (preserve path); #391 `WorkspaceSaveAsContinuationRaceTests` (live edit, tab switch, control; recovery bytes load; guard removal fails 10 expectations) | PARTIAL | Save As lifetime change and disposal during the persistence await; stale cleanup acknowledgement after the lifetime moves |
| R3 | #183 F10 / #378 | A Save As queued behind an encoding-changing save follows the accepted lineage | #392 `WorkspaceSaveAsLineageAdverseOrderTests` (Latin-1, UTF-8 BOM; held at real publication; bytes and returned metadata; inheritance removal fails 4 expectations) | PARTIAL | Destination baseline enforced against an external create during the queue; other encodings are not in scope (supported list not expanded) |
| R4 | #183 / #379 | Watcher bind retry uses the live document's policy; stale lifetimes bind nothing | #393 `ExternalFileControllerBindRetryFlowTests` (real first-watch failure, controlled sleeper, Latin-1 save during the wait, later external edit reconciles; reverting to the captured document fails with the historical symptoms) | PARTIAL | Back-to-back synchronize with a skipped first bind; A→B→A at one URL; deletion after rebind |
| R5 | #183 / #377 | Closed/held/stale Find results cannot authorise replacement or republish | #394 `EditorFindModelHeldSearchTests`; earlier `EditorFindModelStaleMatchTests` (exact-scalar identity, IME marked text, cancel) | PARTIAL | Mounted `FindBarView` live-refresh and closed-bar publication paths; committed IME replacement through the mounted editor |
| R6 | #183 / #381, #382 | IME fail-open; bare-CR/mixed-EOL transforms; one undo transaction | #396 `EditingAssistBareCRTests` (Markdown-assist Tab, Shift-Tab, heading; 7 fail on old source); `EditorMixedSeparatorTransformTests`, `EditorCompositionBoundaryTests` | PARTIAL | App-level JSON-formatting capture/application guards (`WindowCoordinator.performJSONFormatting`: needs a mounted key-window harness; formatted-equals-snapshot check still uses canonical `!=`); Option-click/drag composition is not claimed |
| R7 | #173, #119, #120, #88 | Navigation, external-file, close and Save As UI behave as promised | none executed natively | OPEN | `MacDown2UITests` are built but not run in CI; needs a native UI session |

## Harness trustworthiness

| ID | Owner | Evidence | Status | Missing |
| --- | --- | --- | --- | --- |
| H1 | #159 | #385 typed readiness error + runner cancelled/awaited before teardown; #390 ESRCH-only death checks and a controlled watchdog that releases the real timeout verdict after fixture readiness (lifecycle suite 4/4 at load ≈ 22) | PARTIAL | Other load-fragile TextFilter tests (output-cap race, still-writing descendant under a 2 s bound, `fourth-pass` race) still use wall-clock bounds; a shared async fixture owner for all lifecycle tests |
| H2 | #215 | #386 never-allocatable descriptor | PROVED | — |
| H3 | #163 | #387 `GatedParseEngine`; production busy-state defect reproduced then fixed | PROVED | — |
| H4 | #155 | none | OPEN | Capture the stalled process/run-loop evidence; controlled comparison; no "environment-only" conclusion without it |
| H5 | #203 | #388 corrected benchmark offsets and added a reuse control; Markdown block grammar still ≈ a full parse at 1 MB (≈130–200 ms vs 50 ms budget) | OPEN | Scanner state serialisation / block re-entry; Neon's production edit path; end-to-end Release measurement, or an explicit measured budget disposition from the owner. The issue was closed in error and has been reopened |

## Safety families (handoff A–G)

Not yet proved at their required layer unless listed. The rows below are the starting inventory; each needs the native or fault-injection layer the handoff names.

| Family | Owner | Status | Notes |
| --- | --- | --- | --- |
| A Exact source and truthful save outcomes | #183, FileStore | PARTIAL | Exact-scalar comparisons and encoding lineage covered by unit tests; no full matrix over Save / Save As / Replace in Folder / recovery / export with independent byte reads |
| B Conditional publication and competing writers | FileStore | PARTIAL | RENAME_SWAP fallback ownership, read-back/rollback and `conditionalPublicationRecoveryRequired` have unit coverage; Save As baseline vs external create and rename-during-publication schedules not re-verified here |
| C Metadata and private staging | #174 contract | OPEN | Staging privacy from the first byte is not measured natively; `carryMetadata` runs after staging data is created (source observation, not a demonstrated exposure) |
| D Recovery and session lifecycle | #183 | PARTIAL | See R1–R4; two-snapshot reverse-order publishers, relaunch/retry after each journal transition and the failed-save-then-later-edit schedule are not exercised here |
| E Root authority and contained resource reads | #121 | OPEN | RESOURCE-OPEN native probe, shared reader, immutable contexts, registry/quotas and WebKit proof not started |
| F Destructive folder actions and export ownership | #118 | OPEN | Not started beyond existing unit coverage |
| G Settings and state migration | #53 | OPEN | Compatible settings decoding before any import/bootstrap writer not implemented |

## Not authorised by this work

Credentials or persistent access, signing/notarisation, source-archive publication, deployment, repository cutover and public promotion. #147 (adopted) and `planning/RELEASE_SEQUENCE.md` define the order; the specific authorisation needed will be named when a dependent step is reached.

## Next bounded steps

1. Add the app-level JSON-formatting guard test (needs a mounted key window) and the exact-equality fix.
2. R1/R2/R4 remaining schedules, then repeat on the final head.
3. #121 RESOURCE-OPEN native probe design, then #53 compatible decoding.
4. Idle-machine consecutive serial runs of package and app-target suites once the implementation set is stable.
