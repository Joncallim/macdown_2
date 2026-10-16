# Integration inventory (2026-10-16)

`integration-final` is the integration branch; #480 (draft) proposes it to `master`. Everything below was checked against `integration-final` with
`git apply --reverse --check` (is the PR's whole diff already present?) and `git merge-tree` (does it merge cleanly?). All open PRs are authored by the same GitHub account; the lane names refer to the work, not the author.

| PR | Targets | CI (on its own head vs master) | Already in `integration-final`? | Merges with it? | Disposition |
|---|---|---|---|---|---|
| #480 | master | green on `c1621581` | is the integration | n/a | stays **draft** until the blockers below clear |
| #475 outline focus acceptance (#88) | master | green | **yes, whole diff present** | yes | lands with #480; does not close #88 (broader UITest-gap triage) |
| #472 H5 step 1 measurements | master | green | partly (benchmark files; newer versions present); its register text is superseded by the H5 rewrite | yes (but semantically stale) | **close as superseded** once #480 lands; do not merge |
| #462 architecture for #459 | master | inventory only | no (docs only) | yes | independent docs; can follow #480; does not close #459 |
| #473 TextFilter fixture ownership (#159) | master | green | no; the Codex lifecycle lane is a different implementation of the same files | **conflicts** (2 files) | draft; needs a reconciliation decision |
| #474 folder-search reveal (#173) | master | green | no; overlaps the Codex reveal/focus lane | **conflicts** (3 files) | draft; needs reconciliation |
| #476 Mermaid theme (#79) | master | green | no | **conflicts** (2 files) | draft; reconcile with the integration's renderer light/dark reuse |
| #477 Graphviz theme (#79) | master | green | no | **conflicts** (3 files) | ready on master; reconcile |

## Acceptance checklists
- **Integration (#480) leaves draft when:** hosted CI green on the exact head (done on `c1621581`; re-confirm on the final head); Pinyin native UI suite **run and passed** on a head whose non-test sources equal the final head's (blocked: automation prompt); Release performance suites re-run on the final head with any intermittent failure investigated (one 63.4 ms vs 50 ms failure on `5ccfaf89`, unexplained, two later full runs and three isolated runs passed); the limitations paragraph in the PR is current. Not required for integration, and not done: signed candidate, notarisation, localisation, compliance (release gates).
- **#173/#159 PRs:** pick one implementation per area (this PR or the Codex lane), merge the other's tests as additional coverage if they pass, full package + app suites on the combined head, then the issue's own criteria (native activation/reveal check for #173).
- **#79 PRs:** Mermaid, D2 and Graphviz each follow the app theme in light and dark, with a test per renderer; reconciled with the integration's renderer reuse; native visual check. #79 closes only when all three are done.
- **Pinyin:** `PinyinCompositionUITests` (branch `pinyin-ui-tests`) run to completion: 5 tests plus cancel-across-cut-off; whole-document equality; the pre-test input source restored. Command, from `MacDown2/` in a checkout of that branch:
  `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2UITests/PinyinCompositionUITests test`
- **Issues #53, #203, #459, #88, #79, #159, #173:** none meets its full criteria today; none is closed.

## Where the evidence lives
UI diagnosis: `planning/downstream/evidence/ui-automation-timeout/README.md`. H5: register row H5, `planning/h5-dependency-followup.md`, `planning/downstream/evidence/h5-*`.

## Addendum (2026-10-16, later)
- **#476/#477 vs the integration are a product conflict, not just a textual one.** `integration-final` carries the Codex lane's
  commits "Apply neutral light Mermaid rendering policy" (9db79954), "Use neutral light Graphviz rendering policy" (4c1027cb) and
  "Protect neutral-light diagram rendering" (bf1a91bf): diagrams render with a neutral light policy. #476/#477 instead apply the app
  theme's colours. Merging both is not a conflict-resolution exercise; it needs an owner decision on the intended diagram colour policy
  (and #79's acceptance criteria say "theme-coherent"). Until decided, neither is merged and #79 stays open.
- **Intermittent Release-performance failure (`handledAssistOn1MB`, 63.4 ms vs 50 ms on `5ccfaf89`) investigated.** The test is a single
  `ContinuousClock` measurement of EditorCore code that this integration does not change. Instrumented in a scratch worktree and run as 12
  separate processes in isolation plus 6 inside the full `Performance|MarkdownTreeReuse` filter (18 samples, Release, M3 Pro, load average
  4-7 from background processes): typical 15.9-18.8 ms, two outliers at 30.4 and 38.6 ms. The 63.4 ms failure is a heavy-tail sample of the
  same measurement under machine load, about 3.5x the typical value, not a regression: the median is about a third of the budget.
  The test and its 50 ms budget are unchanged. Making it robust (median/p95 of N samples) would change what it asserts and is left as a decision.
