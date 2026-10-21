# Independent review and bounded performance follow-up

## Owner summary

A separate, read-only reviewer found no concrete regression in the code from
`60f779fc0f7324cd5dd3b7b503030e9c22d7d44f` through
`e16be9f7a749d9ed0f2fd74829483c26c87051f4`. This completes that source-review
step, not performance acceptance or the owner's review. The code remains
byte-identical to the final build/app-test source, `0b85e6f0`.

The fixed performance investigation did not reproduce the 484.814584 ms parser
overrun. Its full-suite invocation instead failed the editing-assist ceiling at
**56.881709 ms against 50 ms**. The experiment stopped at its declared stop
condition; neither failure is explained or discarded. There is no demonstrated
editor speed improvement from this follow-up and no basis for release approval.

## Separate review result

The reviewer inspected committed source, selected negative-control evidence and
eight raw-evidence hashes. It made no edits and ran no builds or benchmarks.
The complete report is retained with the local evidence; this is its summary:

- The cleanup test preserves the original zero-delay whole-call `<150 ms`
  assertion, including timeout handling. The extra cleanup measurement does not
  replace that assertion. The slow-setup negative control fails as intended.
- The highlighting correction permits an eligible idle restoration to remain
  full after subsequent small edits. Early checks, a non-vacuity assertion,
  eventual restoration and rendered-run equality remain enabled.
- Removing the benchmark controller and closing its window follows normal
  disposal. The unchanged budgets and isolated-settings negative control
  support the fixture-lifetime diagnosis.
- The actor annotations and warning fixes introduce no identified unsafe
  isolation escape or behavior regression. The preview classifier retains
  cancellation and main-document filtering with the URL-valued Foundation key.

The reviewer identified a **pre-existing coverage limit**: checks about 100 ms
apart could miss a hypothetical restoration at 150 ms instead of the specified
200 ms. The recorded 30 ms mutation proves detection of that case only. No claim
of complete timing-boundary coverage is made. A deterministic boundary regression
is a future bounded test improvement; a new scheduler abstraction would require
architecture review rather than an ad hoc production change.

UI lifecycle fixes were compiled, not exercised by native UI tests. Preview
classifier tests construct errors; they do not prove actual WebKit failure
delivery. Owner acceptance, hosted CI, the original rendered-run mismatch,
runtime diagnostics, native coverage and release compliance remain open.

## Predeclared context experiment

Before running, `performance-context-plan.json` fixed four invocations:
isolated parser A1, complete performance selection B1, complete selection B2,
isolated parser A2. Each invocation would supply one parser measurement. The
plan required stopping on an unrelated test failure, timeout, missing measurement
or compilation failure. It was a bounded diagnostic, not a replacement green
validation series.

Temporary instrumentation surrounded the existing parser interval and added
wall/thread/process CPU, context switches, resident memory and thermal readings.
The input, UTF-16 edit geometry and existing 400 ms assertion were unchanged.
Heavy work ran serially without an added background benchmark. A1 built the
instrumented test binary; B1 used that same binary with `--skip-build`.

| Measurement | A1: isolated | B1: full performance selection |
| --- | --- | --- |
| Parser wall time | 162.661291 ms | 163.004292 ms |
| Parser thread CPU | 161.126666 ms | 162.883334 ms |
| Parser process CPU | 161.126 ms | 162.883 ms |
| Involuntary / voluntary context switches | 11 / 0 | 21 / 0 |
| Resident bytes before / after | 144,179,200 / 216,596,480 | 179,290,112 / 251,592,704 |
| Thermal state before / after | nominal / nominal | nominal / nominal |
| Command result | exit 0 | exit 1: editing-assist overrun |

Both measurements ran on the main thread with 1,000,009 UTF-8 bytes and UTF-16
units. The binary SHA-256 was
`476bb6a670deae444aebae10e0332f9efb05759fd47b4d2043020e0fa1e56fa1`.
A1 began at 2026-10-18 18:12:34 UTC; B1 began at 18:13:00 UTC. Exact commands,
times, patches and log digests are in [review-validation.json](review-validation.json).

B1 failed `EditingAssistPerformanceTests.handledAssistOn1MB` at line 88.
**B2 and A2 were not executed.** The successful parser samples do not establish
why the original parser interval exceeded 400 ms, nor whether suite context
contributed. No measurements exist for CPU or scheduling during that original
slow interval. Nominal thermal state in these samples is not evidence about it.

Source inspection shows the editing-assist interval includes the newline
decision, application through the native text adapter and its success assertion.
The adapter can perform undo-boundary work, text insertion and selection updates.
The failed run has no phase measurements, so none is assigned as the cause. This
benchmark and the parser benchmark are unchanged from the integration base.
The 50 ms assertion remains intact; no assertion was moved outside the timer.

The instrumentation was restored byte for byte, the lock stayed unchanged and
the worktree was clean at `e16be9f7` afterward. The instrumented derived binary is
retained as evidence: do not use another `--skip-build` invocation as proof of
the restored source; rebuild normally before further execution.

## Next independent issue

The next safely separable preparation slice is **#148's Mermaid bundle
provenance**, following `compliance/MERMAID_NESTED_AUDIT.md`. That audit already
records the release-lock versions; repeating dependency-range resolution alone
would not complete it. The remaining step is to obtain the official generated
artifact/source map, prove which direct and transitive packages the exact bundle
embeds, and capture their versioned licence/notice texts. The existing bundle
must retain SHA-256
`581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`.

Read-only preparation can continue independently of parser correctness and
desktop availability. After the module-to-artifact linkage is established,
update the inventory, required licence texts, generated notices and software
bill of materials together, then run the compliance tooling/tests. Stop at any
bundle mismatch or unresolved source linkage; do not infer actual inclusion
from a declared dependency or lock entry. Do not change runtime files, pins or
verified status merely to reduce the release ledger.

This slice does not authorize publishing sources or binaries. The existing
font-set KEEP decision is recorded in issue #148 comment 5868785863 and
`compliance/RELEASE_PREPARATION.md`; the remaining work there is inventory and
artifact reconciliation, not another request to choose the font set. Tomorrow
Light's naming/provenance decision remains with E23. All eight current release
checker failures and all 22 open issues remain open at this checkpoint.

## Evidence location and external state

Raw review and experiment evidence:
`/Users/jonathanlim/GitHub/_cleanup-archive/astra-review-e16be9f7-2026-10-18/`.
The record includes the plan, script, source backup, instrumentation patch,
individual logs and restoration checks. Earlier failed and successful runs
remain at their original locations and retain their actual source identities.

No push, PR edit, merge, release, signing, notarisation, source publication,
upstream submission, issue closure or deletion of unique work occurred. The
proposed draft PR #480 update remains unposted. Independent source review alone
does not authorize that external change or waive the failed performance gate.
