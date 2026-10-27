# Focused local real-client ordering diagnostic

This is an isolated CORTANA diagnostic, not a production scheduler fix or new dependency version. It extends the pinned Neon diagnostic overlay with real TreeSitterClient query/edit coverage. The application, production lockfile, cutoffs, workflow and original fatal preconditions are unchanged. Nothing here authorizes or triggers another hosted run.

## Contents and source provenance

- `ordering-diagnostic.patch`: existing revision-2 instrumentation against Neon `dabf50c947148c49acd0d321dfe8f3805d10b3da`, SHA256 `8fcd517bcefba2b6704fd19297ea9d5779cf279f04cce994eeb3e0299e3ff986`.
- `real-client-harness.patch`: incremental diagnostic changes and tests on that overlay, SHA256 `bbe1695beb97a2074bfdfbd25353208b19f5db0a14631805e4ba89474eeee26d`. It adds metadata labels, not scheduling operations, to the ordinary query path. Gate-based controls are opt-in; the two new ungated cases install no gates.
- `real-client-Package.swift`: exact small validation manifest, not an app package or production dependency manifest. `real-client-source-SHA256.txt` records all 30 generated Swift source hashes used by the passing focused run.
- `prepare_real_client_local.py`: reconstructs only three small Neon source targets and the diagnostic tests from the existing retained clean sources plus both patches. It copies Neon's license and retains a grammar symlink. No clone or full product checkout is created; existing overlays are never overwritten.
- `run_real_client_incremental.py`: checks the mounted SSD/external common Git root and intended branch ancestry, uses the one existing scratch, caps compile/test time, disk and logs, and supervises only directly owned live Popen children. No process-group probe/signal or global permission change.

Dependencies are read-only retained checkouts at `/private/tmp/mt-preview-fix-bft-derived-2026-10-26/SourcePackages/checkouts`: Rearrange `4de8be41dba304192e87dc0a11e0aa39e72aa2e8`, SwiftTreeSitter/SwiftTreeSitterLayer `cbe31cb3601aa29c1f64b6e4328733511126d6d5`, tree-sitter `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406`. Neon's test Swift grammar is submodule `50b8c5e61c29fa30e760c7a1cbf24b59970e6233`. These are the same relevant graph used in earlier local validation, not Neon's older standalone resolution. SwiftPM's explicit local tree-sitter identity-override and unused-direct-dependency warnings remain disclosed. No production pin was changed. Neon licensing/provenance remains in the pinned source and the repository's existing compliance records; these sources are not bundled into the app by this diagnostic.

## Reproduce safely on the existing CORTANA paths

From this directory, with Fast SSD mounted and the retained source checkouts present:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 prepare_real_client_local.py --check
```

For a fresh missing small overlay, omit `--check`. It refuses an existing target and validates exact source/dependency/grammar identities. The creation path is source-reviewed; the read-only check and patch-application checks were exercised on the existing overlay.

The runner deliberately requires the existing evidence/scratch directory `/Volumes/Fast SSD/CORTANA-Builds/neon-real-client-2026-10-27`. Preserve all numbered prior attempts and select one new explicit attempt identifier for an intentional focused check:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 run_real_client_incremental.py --attempt 6
```

The example is not an automatic rerun instruction. Compile is bounded to 600 seconds; the filtered RealClientOrderingTests helper to 60 seconds; each log to 1 MiB; reserve 8 GiB and per-stage footprint budget 2 GiB. Tests start only after compile passes. Child-local `DYLD_FRAMEWORK_PATH` references the installed root-owned Xcode Testing.framework directory, matching the framework needed by SwiftPM's test helper; no global environment or bundle rpath is changed. On a permission denial or uncertain process state, stop that action and inspect rather than using another signal route. Direct-child supervision does not claim general descendant containment; timeout/kill branches were not exercised by the successful runs.

## Exact invariant and actual observations

The tests retain callback identity/order/exactly-once checks, immutable query/read snapshots, pending-state balance, zero trace eviction and nonzero parser reads. Normal-order real-parser results must match a fresh parser. The diagnostic-only warm-up join handles one validation enqueued synchronously by this fixture before installing gates; it is not a general quiescence API. The controlled inverse-order test observes the mismatch before invoking the fatal consumer out of order, then drains callbacks FIFO. It is not a natural reproduction.

The ungated cases use Swift source at 4,096 and 32,768 UTF-16 units. They correlate a `queryIssued` label to its specific pending worker request, then issue two distinct edits immediately in one MainActor turn. They never hold, release, reorder or gate submissions/callbacks. Snapshot receipts are metadata-only signatures of actual parser-read bytes; no source text enters the trace.

Local Xcode 26.6 / 17F113, incremental attempt 5: compile PASS in 6.408 seconds; helper PASS in 0.382 seconds; Swift Testing reports four test functions, including both ungated sizes and both controlled inversion cases, in 0.243 seconds. Source hashes remained unchanged; no resource/log bound crossed. Logs and metadata are retained under the existing scratch root. `real-client-unforced-evidence.json` contains the compact boundary sequences, not a replacement for the raw logs.

Both ungated traces had matching request/execution/callback sequences `[3,4,6,9,12,15,17,18]` and asynchronous submission/resume sequences `[3,4,6,9,12,15]`. The labelled query was request 9. In the 4,096 case it was requested at sequence 31; mutations enqueued at 32/34 with pending count reaching 2; its callback arrived at 43. In the 32,768 case those positions were 59, 60/62, and 71. Both traces had zero eviction (64 and 92 events). The edits were requested before the query's worker submission: this proves pending-query coverage, not edits occurring during an already executing query.

## Limits and smallest next production-level test

No spontaneous ordering mismatch reproduced in these observed executions. They demonstrate that an outstanding query plus two queued mutations does not deterministically fail this local Swift grammar/client pipeline. They do not rule out other scheduling interleavings, Markdown injections, cold-start/discard/rebuild lifetimes, older Xcode 26.0.1 behavior, or tracing perturbation. The warmed fixture intentionally excludes predecessor-editor work; a passing controlled inversion test is not production acceptance.

The smallest next production-level test is the actual Markdown HighlightedEditor path with ungated lifetime/operation tracing: run the existing discarded-highlighter queued-work lifecycle case followed by `belowTheCutoffHighlightingMatchesAFreshHighlighter` in one bounded local focused process. Preserve their original timing, teardown and assertions—do not add the isolated fixture's warm-up join or sleeps to production tests. Record every editor/client lifetime so a stale predecessor's completion cannot be blamed on the active test merely from buffered output order. A divergence must identify the first difference among mutation request order, worker submission/execution order and callback consumption before proposing any production sequencer or dependency change. This follow-up has not run as part of these results.

## Executed-query callback-pending coverage (local attempt 6)

The preceding results remain historical. The current ungated case is
`ungatedExecutedQueryAndTwoEditsPreserveOrdering`, at the same 4,096 and 32,768
UTF-16 sizes. It requires the labelled query's worker execute event with its
callback still absent. Missing the natural window is explicitly inconclusive
and fails the coverage requirement. No gate, sleep, hold, warm-up or production
scheduling change was added. Existing snapshot/fresh-parser/order/exactly-once
assertions remain, plus post-run sequence and two-pending-mutation requirements.

Local attempt 6: compile PID98895 exit0 in14.365s; selected helper PID99060
exit0 in0.376s. Swift Testing reports one function/two cases passed in0.220s.

| UTF-16 units | Query execute | Edit A | Edit B | Query callback | Pending |
| --- | --- | --- | --- | --- | --- |
| 4096 | 33 | 36 | 38 | 40 | 2 |
| 32768 | 61 | 64 | 66 | 68 | 2 |

The worker had already finished/resumed before the edit burst; the actor callback
was outstanding. This is not proof of concurrent parser reads during edits.
Gates stayed unset, no eviction/truncation occurred, and all30 source hashes
were stable. CORTANA toolchain is Xcode26.6/17F113, Swift6.3.3. No ordering failure
was reproduced and no original-Xcode26.0.1 or production acceptance is claimed.
No hosted run was started for this change.

The existing runner gained only a --test-filter option. The executed command was
PYTHONDONTWRITEBYTECODE=1 python3 run_real_client_incremental.py --attempt 6 --test-filter RealClientOrderingTests.ungatedExecutedQueryAndTwoEditsPreserveOrdering.
It did not execute controlled gate/inversion cases. Preserve incremental-6-{compile,focused-tests}.log and
incremental-6-metadata.json in the existing SSD evidence directory. Do not retry
that occupied slot. Current patch SHA256:
e77b43ab7e64476c2c3c85e66b772c298736751eadba1d9d8a7640f9aa6035a9;
current source-manifest SHA256:
1ebb6d27976b52a96c8082c5a776f7a73d58b8f42c55710b400493f96d7addfb.
