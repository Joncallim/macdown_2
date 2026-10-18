# Combined candidate validation, 18 October 2026

## Owner summary

The local candidate passed the package suite, three serial Release performance
runs, unsigned Release app/CLI builds and non-UI app-target tests. This does not
make integration ready: the full app-target run exposed a 103-second window-close
test delay, the test build reports existing warnings, hosted CI is still red on
the preceding head, and independent/owner review is pending. No threshold, test
skip, dependency pin or production highlighting policy was weakened.

The timing corrections add no editor-visible capability. The production cleanup
uses Foundation's current failing-URL key when deciding whether a failed main
preview load can retry, removes an unused export length calculation and redundant
typed catch, and preserves close-sheet coordinator existence checks without
unused bindings. The earlier repaint fix remains integrated; the Markdown
highlighting cutoff stays at 8,192 UTF-16 units.

## Provenance and ownership

- Ownership was accepted after the explicit Claude handoff and process/worktree
  inspection on clean integration `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`.
  An earlier active Claude job was left untouched until that handoff.
- Work is preserved locally on `fix/ci-timing-contracts` in
  `/Users/jonathanlim/GitHub/macdown_2-integ`.
- `90402ea5d42d24c6773afa6381c1d483cd16de3b` corrects timing assertions and
  cleanup measurement. Its first serial package/performance/build sequence
  passed, but the Release app build exposed five production Swift warnings.
- **Final tested code: `f9f9926ff07d7e8550fa703f329d7e0f943d16a2`**, adding the
  warning corrections and preview error classification regression. All commands
  below verified that head and a clean tracked working tree before and after.
- CORTANA: M3 Pro, macOS 26.5.1, Xcode 26.6, Swift 6.3.3. Builds ran serially.
  Package builds used `--force-resolved-versions`; Xcode builds used the copied
  lock plus `-onlyUsePackageVersionsFromResolvedFile`. The final pin check passed.
- The later documentation commit only adds/reconciles evidence. Its `MacDown2`
  subtree is byte-identical to the tested code; results belong to the code head
  above and are not relabelled as a new test execution on the documentation head.

## Recorded outcomes on the final code head

| Validation | Outcome | Limits |
| --- | --- | --- |
| Full package `swift test --no-parallel --force-resolved-versions` | Exit 0; 237.530 s test execution | Two pre-existing known Neon replacement-edit issues remain. Existing opt-in benchmark skips and the Debug-disabled widened-background experiment remain unchanged. This is not a full Release package run. |
| Release `Performance\|MarkdownTreeReuse` filter, three planned serial runs | All exit 0; command durations 20.595 / 6.914 / 6.566 s | Includes compilation/startup; does not prove fully highlighted large Markdown meets #203. No failure was retried to obtain these passes. |
| Unsigned Release app and CLI builds | Both exit 0 | The five production Swift warnings are gone. Xcode's AppIntents metadata tool still reports no AppIntents dependency. No signing/notarisation/install proof. |
| Build for testing | Exit 0 | UI tests compiled but were not executed; warning inventory below remains open. |
| Non-UI `MacDown2Tests` | Exit 0; 149.232 s test execution | The preview URL-error test passed. The window-close delay below prevents treating this as uneventful validation. |
| Strict SwiftLint and SwiftFormat lint | Both exit 0 | Compiler/runtime diagnostics are separately recorded below. |
| Clean committed-source compliance | Exit 0 | Executed from `git archive` of the exact commit, avoiding generated working-directory artifacts. |
| Release compliance preflight | Exit 1; eight unresolved items | Preserved as failed evidence, not waived; see the open-issue register. |

The [machine record](candidate-validation.json) contains the actual commands,
timestamps, source identities, outcomes, diagnostic summary and raw-log hashes.
Local raw evidence is retained at
`/Users/jonathanlim/GitHub/_cleanup-archive/astra-validation-60f779fc-2026-10-18/`,
with the final sequence under `final-f9f9926f/`. Earlier mutation evidence is
described in [README.md](README.md); expected failures are distinct from passing
validation.

## Window-close observation requiring diagnosis

`WindowCloseRetiredLifetimeTests.anEditDuringASuccessfulCloseRetireLeavesTheWindowRecoverable`
passed after **103.099 seconds** in the full run. Before that test, tab-scale
tests emitted AppKit warnings about reentrant operations in an NSTableView
delegate. These are observations, not proof that the preceding test caused it.

Two five-second samples were collected while the test was not advancing:

- At 17:18:29 UTC, the main thread was sampled in SwiftUI/AttributeGraph update
  work; physical footprint was 3.7 GB. This sample contained no NSAnimation frames.
- At 17:19:06 UTC, footprint was 4.5 GB; the sample contained both AttributeGraph
  and animation activity. Neither sample reported the prior dispatch soft-limit
  pattern. Sampling can perturb timing; this is not a measured end-user latency.

The same test process resumed and completed without interruption or rerun.
One explicitly scoped follow-up ran only that test on the same clean code head:
**0.894 seconds**, exit 0. This establishes a full-suite versus isolated contrast,
not the causal mechanism. Both observations stand. A bounded suite-order/window
lifetime investigation belongs with #155/#183 before release readiness; do not
rewrite this as an unexplained flake or hide it behind the successful exit code.

## Test-build warning gate

The build-for-testing log contains 277 actor-isolation warning occurrences across
12 UI-test files, an unused `try?` result in `ExternalFileChangesUITests.swift`,
24 dependency-scan warnings, a cmark umbrella-header warning and 15 AppIntents
metadata-tool messages. Counts are diagnostic occurrences, not distinct defects.
The full messages are saved in `final-f9f9926f/test-build-warnings.json`.

Inspected UI tests are `@MainActor` XCTest classes with synchronous `setUp` and
`tearDown` overrides using actor-isolated properties. Fix those lifecycle
boundaries in a focused #88 slice and verify the native harness. Investigate the
dependency-scan diagnostics against the real SPM graph before changing module
dependencies; do not add cross-module dependencies or lower concurrency checking
just to silence them. The repository's warning requirement remains unsatisfied
for this test-build surface.

## Hosted, native and release gates remain separate

The complete job log for run
[39145925261](https://github.com/Joncallim/macdown_2/actions/runs/39145925261)
confirms synthetic merge `094e83abe5e8fd1468ff69ad0f1ce3de97ce5b05` containing
`60f779fc`: cleanup took **176.18825 ms against 150 ms**. Highlighting passed;
lint passed; app/CLI build and app-test steps were skipped. Neither this overrun
nor the earlier 160.1835 ms overrun has an established cause. The original
rendered-run mismatch from run 39140426985 also remains unexplained. No hosted
workflow was rerun by this task, and no hosted result exists for the new code.

Manual Simplified Pinyin proof remains the Debug-only record in
`../pinyin-native-manual/`. It does not establish automated CJK coverage, other
input methods, candidate mouse interaction or long composition during restore.
No final native UI run, signed artifact, migration/update rehearsal or final
licensing approval is claimed. #53 and #203 remain open.

Independent review of the new local commits and the owner's review are pending.
Recommended next work is the bounded stall/warning investigation and independent
review, then explicit authorization to update `integration-final`/draft PR #480
for fresh hosted CI. No push, PR mutation, merge, release, signing, notarisation,
upstream submission or deletion of unique work occurred.
