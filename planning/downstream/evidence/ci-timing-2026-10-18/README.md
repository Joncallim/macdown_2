# Timing-test review after the integration checkpoint

## Owner summary

The editor's production behavior is unchanged. These test corrections distinguish a legitimate return of syntax
colors after an idle pause from premature restoration, and retain the original whole-call cleanup assertion
while measuring setup and cleanup separately. The 200 ms test idle delay, 25 ms watchdog, 150 ms cleanup bound,
production 8,192 UTF-16 cutoff, and dependency pins are unchanged. This work does not establish why the hosted
runner exceeded the cleanup bound.

The [follow-up review](FOLLOWUP.md) records the final local code, the reproduced window-fixture repair and
a new failed Release performance gate. It also corrects the initial cleanup-only measurement described in
the earlier checkpoint. The candidate is not integration-approved.

The base is `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`, containing PRs #488–#491. Its latest hosted result is
**failed**, not passed. Owner review and new hosted evidence remain required before integration readiness.

## Hosted evidence

- [Run 39140426985](https://github.com/Joncallim/macdown_2/actions/runs/39140426985) tested synthetic merge
  `9dd3436be84e67b5da1c8c8282b6f042d63aa75b` of candidate `8b324fb14cc82fa3dbec04203f9ea18e24985d46`
  into master `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. It recorded four `.full` versus `.reduced`
  failures during simulated typing, a rendered-run mismatch, and cleanup taking 160.1835 ms against 150 ms.
- [Run 39145925261](https://github.com/Joncallim/macdown_2/actions/runs/39145925261) tested synthetic merge
  `094e83abe5e8fd1468ff69ad0f1ce3de97ce5b05` of candidate `60f779fc` into that same master. Its
  build-and-test job `117729630575` failed on cleanup taking 176.18825 ms against 150 ms. The highlighting test
  passed in this run. App/CLI build and app-test steps were skipped. Lint and the separate compliance workflow passed.

A subsequent local pass does not replace either failure. Neither cleanup delay has an established cause.
Oversleep is a plausible explanation for the original highlighting failure, not a proven reconstruction of that run.
The original rendered-run mismatch is also not explained by the controlled reproduction below.

## Review findings and bounded local evidence

The unmodified `60f779fc` candidate passed the focused Debug filter below on CORTANA (M3 Pro, macOS 26.5.1,
Xcode 26.6, Swift 6.3.3). All 22 package checkouts matched the committed lock and had clean working trees.

### Restoration after an eligible idle pause

PR #491 made the pre-edit assertion conditional on elapsed time, but left an unconditional reduced-mode assertion
after each edit. Once a real idle pause has restored highlighting, subsequent small edits correctly leave it full.
The next short pause must not treat that already-full editor as if it were still awaiting restoration.

Two controlled test-only probes retained the production implementation:

1. Extending the second pause to 300 ms passed: the preceding insertion put the document one UTF-16 unit above
   the restore threshold, so no restoration was scheduled. This is useful threshold evidence, not a reproduction.
2. Extending the third pause to 300 ms reproduced the assertion defect. That pause followed a deletion to the
   restore threshold; it resumed after 306.12 ms in full mode. The original test failed three assertions even though
   no early restoration occurred. Rendered runs matched the fresh highlighter in this probe.

The corrected test covers both the ordinary typing sequence and the third-pause scenario. It checks the minimum
idle delay only when the previous edit left the editor reduced, and verifies that each small edit preserves the
mode present immediately before it. The qualifying-pause guard and final rendered-run equality remain intact.

A temporary production mutation restoring after 30 ms instead of the policy delay failed the corrected test's
early-restoration assertion in both cases. The mutation was restored byte for byte afterward.

### Preserve the whole-call bound and diagnose cleanup separately

The initial local change in `90402ea5` moved the stopwatch to the end of the fixture body. That preserved the
number 150 ms but dropped the original zero-delay call-to-result guarantee. Fresh author review identified
this weakening; `98582785` restores that original assertion and reports setup and cleanup intervals separately.
A deliberate 200 ms setup case additionally checks the cleanup interval, including cancellation dispatch.

A temporary 200 ms pre-body delay now fails the whole-call assertion at 235.71525 ms even though cleanup takes
29.53475 ms. A separate earlier mutation moved blocking cancellation outside the watchdog: both cases failed
at approximately 206/204 ms against 150 ms. All mutations were restored byte for byte. The 25 ms watchdog,
150 ms bound and production timeout code remain unchanged.

Neither phase was timed in the hosted logs, so setup and scheduler hypotheses remain unproved. The added
measurement supports diagnosis; it does not establish a fix for the hosted cleanup failures. See the
[follow-up](FOLLOWUP.md) for the exact contract and negative-control records.

## Validation and remaining gates

The corrected focused filter passed. The expected-failure mutation runs above are separate evidence, not passing
validation. Raw logs, mutation patches, restoration hashes and environment provenance are retained locally at
`/Users/jonathanlim/GitHub/_cleanup-archive/astra-validation-60f779fc-2026-10-18/`.

From `MacDown2/Packages/MacDownKit`:

```sh
swift test --no-parallel --force-resolved-versions --filter 'HighlightingSizeFallback|HighlightingRestoreRepaint|StaleWorkAfterCrossing|TextFilterFixtureCleanupSafety'
swift test --no-parallel --force-resolved-versions
swift test -c release -Xswiftc -enable-testing --no-parallel --force-resolved-versions --filter 'Performance|MarkdownTreeReuse'
```

The earlier serial validation is recorded in [VALIDATION.md](VALIDATION.md), with exact code head
`f9f9926ff07d7e8550fa703f329d7e0f943d16a2`, raw-log hashes and remaining warnings/stall observations.
It includes one full package run, three Release performance runs, unsigned app/CLI builds and non-UI app-target
tests. Later exact-head results and the failed Release performance series are in [FOLLOWUP.md](FOLLOWUP.md).
Successful local exit codes do not replace the failed hosted evidence. No hosted rerun or push is authorized
by this evidence record.

The earlier 63.4 ms Release outlier is consistent with the recorded load investigation, but its cause is unproven.
Manual Simplified Pinyin coverage remains the Debug-only scope documented in `../pinyin-native-manual/`;
automated CJK coverage, other input methods, candidate mouse interaction and long compositions during restore
remain unverified. Issues #53 and #203, owner policy decisions for #473/#474/#476/#477, and the independent
release gates remain open. These test-only changes add no editor-visible capability.
