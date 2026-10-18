# Handoff to Astra (updated 2026-10-19): MostlyText integration + highlighting

Written by Claude (Sonnet) at a bounded checkpoint. **Nothing here authorises a merge to `master`, a release, an upstream submission, or adopting an experimental dependency.** #480 stays a draft; #53 and #203 stay open. Every result is labelled with the commit it was observed on. Items with an unestablished cause say so.

## 1. Exact heads
| Ref | Commit | Notes |
|---|---|---|
| `master` (remote and local) | `4aa46bfa` | unchanged |
| `integration-final` (remote and `/Users/jonathanlim/GitHub/macdown_2-integ`) | `60f779fc` | PR #480 head; local worktree clean, equal to remote |
| `dep-trial` (experimental, pushed; worktree `/Users/jonathanlim/GitHub/macdown_2-deptrial`) | `1ec1c212` plus this file's commit | dependency/Neon experiments, wiki draft, handoff; **not** part of the integration candidate |
| `pinyin-ui-tests` (pushed, unmerged) | `4cc7a262` | XCUITest suite that cannot drive an input method; kept for reference, do not merge as is |
| `checkpoint/janet-integration-bf1a91bf` + tag | preserved | handoff checkpoint |
| Worktrees | main clone (`master`), `macdown_2-integ` (`integration-final`), `macdown_2-deptrial` (`dep-trial`) | all clean when written |
Open PRs: #480 (draft), #477, #476 (draft), #475, #474 (draft), #473 (draft), #472, #462; their relation to `integration-final` is in `planning/INTEGRATION_INVENTORY_2026-10-16.md`. Branch-cleanup record: `/Users/jonathanlim/GitHub/_cleanup-archive/`.

## 2. CI on #480, by tested commit (pull_request runs test the merge of the head into `master` `4aa46bfa`)
| Head | Tested merge commit | Run | Result |
|---|---|---|---|
| `c1621581` | (earlier) | 38852867830 | passed (lint, build-and-test, inventory) |
| `0d877446` | (earlier) | 38921442673 | passed |
| `15119add` | n/a | 39140380380 | cancelled (superseded by the next push) |
| `8b324fb1` (after #488 repaint fix and #489 evidence) | `9dd3436` | **39140426985** | **FAILED** build-and-test (job 117713614419): 2584 tests, 8 issues including 2 known = **6 real issues in 2 tests** (below) |
| `a29673b9` (after #490) | `41cb8a5` | 39142226248 | passed, including both tests that failed above |
| `60f779fc` (after #491) | `094e83a` | **39145925261** (job 117729630575) | **FAILED** build-and-test: one failing test, `cleanupDeadlineIncludesBlockingCancellationDispatch` at `TextFilterFixtureCleanupSafetyTests.swift:161:9`, `0.17618825 seconds` against `150 ms` (log line 8897). `shrinkingBelowTheRestoreThreshold…` and the rest passed on this run |
A green rerun on `a29673b9` shows the failures are not deterministic; it does not establish their cause.

### Run 39140426985: what it actually recorded (complete job log, saved gzipped at `_cleanup-archive/ci-39140426985-job117713614419-full.log.gz`)
1. `shrinkingBelowTheRestoreThresholdRestoresOnlyAfterIdle()` (log lines 7533-7536): **four** `Expectation failed: (editor.mode → .full) == (.reducedForTestPolicy …)` at `HighlightingSizeFallbackTests.swift:162:13`, i.e. the document was already restored inside the typing loop (**too early**, not late); then line 7537 a `renderedRuns()` mismatch at `:169:9`; line 7539 "failed after 3.005 seconds with 5 issues".
2. `cleanupDeadlineIncludesBlockingCancellationDispatch()` (line 8921): `TextFilterFixtureCleanupSafetyTests.swift:161:9: (started.duration(to: .now) → 0.1601835 seconds) < (.milliseconds(150))`; line 8922 "failed after 0.287 seconds with 1 issue". Final line 10136: "Test run with 2584 tests in 343 suites failed after 292.472 seconds with 8 issues (including 2 known issues)".
**Discrepancy with my earlier summary, owned:** I first read only a partial `gh run view --log-failed` export (it showed just the first test), read `:162` as the final "should be restored" check and described a "late timer" restore, and reported one failed test. The complete job log shows an early restore (four times) and a second failed test. My description was wrong on both counts.

### What each failure is (and is not) known to be
- **Early restore:** the pauses are `settle(100 ms)` sleeps against a 200 ms idle delay. On a loaded runner a 100 ms sleep can last more than 200 ms, in which case a real idle period elapsed and restoring is correct. That is consistent with the log (the failures are in the typing loop and the document was restored). It is a hypothesis about timing, not proven from the log; the product code schedules the restore from the last edit and cancels on every edit, and I found no early-fire path.
- **#490** (`a29673b9`) replaced fixed sleeps with polling for the *eventual* restore. That does not address the early-restore assertion, which was the actual failure. **#491** (merged, `60f779fc` ancestry) fixes the assertion: "still reduced" is now required only while less than the idle delay can have elapsed since a timestamp taken before the last edit, and the test fails if no pause ever qualified. Mutation check: restoring after 30 ms fails it (including the "an edit just happened" check). #490's polling is kept.
- **Cleanup deadline (160.18 ms vs 150 ms): cause NOT established, test unchanged.** It measures how long the fixture-cleanup watchdog (25 ms timeout) takes to throw while a cancel handler blocks for 200 ms; the bound sits between the two. I could not reproduce it: 8 runs without load and 12 under 14 busy-loop processes all passed (total test time 0.205-0.218 s). It may be scheduler latency on the hosted runner, or a real delay; neither is shown. It failed again on the next hosted run (176.19 ms, run 39145925261, tested merge `094e83a`) and passed once (run 39142226248): 2 failures in 3 hosted runs, 160.18 and 176.19 ms, never reproduced locally. It deserves its own investigation (e.g. measure the throw time distribution on the runner) and I did not widen the bound or dismiss it.

## 3. Local validation, by commit (not for the final head)
- `d42f2723`: package 2580 tests/342 suites (2 known), MacDown2Tests 393/83, Release app+CLI, native UI 37/37 (`planning/downstream/evidence/ui-native-run-d42f2723/`).
- `4ee6ff03` (restore-repaint fix, PR #488): format/lint clean, package 2584/343 (2 known), MacDown2Tests 393/83, Release app+CLI.
- #491 test change: `HighlightingSizeFallbackTests` 10/10 locally; the full package suite was run for #490 (2584/343) but **not** re-run for #491.
- Final head `60f779fc`: no full local run; its differences from `d42f2723` are tests, the repaint fix, docs.
- **Manual Pinyin evidence (hand-driven, not automated, on the Debug app built around `0d877446` and then the fix):** `planning/downstream/evidence/pinyin-native-manual/`. It found the restore-repaint bug (fixed in #488, re-verified live).

## 4. Remaining failures / unknowns
- cleanup-deadline timing failure (above); the early-restore diagnosis is a timing hypothesis.
- **Release performance:** the last full run was on `5ccfaf89`; one failure `handledAssistOn1MB` 63.4 ms vs 50 ms. Later investigation (inventory addendum): 18 instrumented runs, typical 15.9-18.8 ms, outliers 30.4 and 38.6 ms. So: **consistent with load-noise outliers, cause not proven**, the test and its limit are unchanged. (My earlier handoff text said "explained"; that overstated it.)
- #480 blockers: CI re-confirmation on the final head, Release-performance rerun on the final head, owner review, release gates (signing, notarisation, localisation, compliance) which are separate and not started.

## 5. Commands for the final Release-performance validation (from `/Users/jonathanlim/GitHub/macdown_2-integ/MacDown2/Packages/MacDownKit`, on `integration-final`)
```
swift test -c release -Xswiftc -enable-testing --no-parallel --force-resolved-versions --filter 'Performance|MarkdownTreeReuse'
```
Repeat at least three times on a quiet machine, record each run's duration lines and any failure verbatim, and investigate rather than rerun-until-green. Then, from `MacDown2/`: `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -configuration Release -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile build` and the same with `-scheme macdown2`. Gates that need a person at the Mac: native UI suite (`-only-testing:MacDown2UITests`), which needs the screen free and the automation prompt answered.

## 6. Experimental, kept separate
`dep-trial`: Neon/tree-sitter/SwiftTreeSitter experiments (`planning/h5-dependency-followup.md`, `planning/downstream/evidence/h5-*`), the wiki draft (`planning/wiki-draft/`), no production pin changed. tree-sitter's contributing policy forbids agent-opened issues and PRs; `planning/upstream/tree-sitter-lexer-goto/` is for a human. The 8,192-UTF-16-unit fallback is unchanged.

## 7. Ownership
**Observed 2026-10-19:** after my last fast-forward, the `macdown_2-integ` worktree was switched to branch `fix/ci-timing-contracts` with uncommitted edits to `HighlightingRestoreRepaintTests`, `HighlightingSizeFallbackTests`, `SizeFallbackTestSupport` and `TextFilterFixtureCleanupSafetyTests` (a parameterised `setupDelay` version of the cleanup test). I assume that is Astra's work and did not touch the worktree, did not push to `integration-final`, and did not act on the Autofix CI event; please confirm.

Claude's last actions: merged #488, #489, #490, #491 into `integration-final`; saved this checkpoint to `dep-trial`. Astra should independently review the final diff and evidence, finish exact-candidate validation, and make the release-readiness recommendation to the owner.
