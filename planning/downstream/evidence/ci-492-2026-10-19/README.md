# PR #492: unresolved styling and cleanup failures

PR #492 remains blocked. Its first hosted attempt reproduced both problem areas from the integration handoff: the restored editor had incorrect syntax styles after editing, and fixture cleanup missed its timing bound. No product fix, dependency adoption, assertion relaxation or acceptance completion is claimed here.

## Exact candidate and complete log

- Source: `3236a61ecb784e7015debb0aa514640a811f0770`.
- Base: `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`.
- Tested merge: `b7c6d59ec933b62dc6d7e64e340f391e94bd4b16`; source and tested merge tree: `cab3f02c4d468686324e59e69caece0558c998a8`.
- [Hosted run 39176035861](https://github.com/Joncallim/macdown_2/actions/runs/39176035861), job `117818784189`, attempt 1, Xcode 26.0.1 build 17A400. Normal exit 1; no crash shown.
- Complete raw job log SHA-256: `2059cc5d116f9ed402debd8b7fc1e062b90562080b73c091662f8ebe5ddfcf71`. CORTANA archive: `/Users/jonathanlim/GitHub/_cleanup-archive/issue-review-2026-10-19/pr-492-job-raw-refreshed.log`.
- The initial combined `gh run view --log` export was incomplete. Retrieve the raw job endpoint with `gh api repos/Joncallim/macdown_2/actions/jobs/117818784189/logs --allow-escape-sequences` redirected to a file; do not infer missing tests passed from the combined export.

The restored-editor comparison failed at `HighlightingSizeFallbackTests.swift:185`, with `includesIdlePause=true`. Early-restoration assertions passed. Its styled-run difference is exactly the same as the recorded difference in original run 39140426985 at line 169: wrong runs around offsets 109–271. The initial 2,000-unit deletion happens in reduced mode and is withheld from Neon; the added idle pause can allow the final two small edits at offset 50 to reach Neon after restoration. The original hosted log did not record the mode history; the diagnostic timeline will establish the actual sequence. The existing collapsed-range replacement defect is not an established explanation.

Cleanup failed at `TextFilterFixtureCleanupSafetyTests.swift:179`: `cleanupElapsed=0.152564667 seconds`, against 150 ms, after separately measured setup of `0.220659166 seconds`. Thus setup overhead does not explain this failure. The zero-delay case passed. Historical 160.18 ms and 176.19 ms failures remain unexplained.

The full run reports two unexpected issues and two unchanged known Neon issues. Lint and ordinary compliance passed. Subsequent app/CLI builds and app tests were skipped. This intermediate stage retains eight release-ledger findings; ordinary compliance success is not release compliance approval.

## Local evidence and isolated dependency probe

One local baseline of the two failing tests on clean tracked source `3236a61e` passed. It neither reproduces nor explains the hosted failures. CORTANA uses Swift 6.3.3 / Xcode 26.6, unlike the hosted runner's Xcode 26.0.1.

Independent source review found that pinned Neon's `TokenSystemValidator.validate` checks the content revision before awaiting tokens, then applies them without checking the revision again. `TextViewHighlighter` uses this validator. The adapter's generation guard rejects discarded highlighters, but ordinary edits retain that generation.

The isolated probe copies the pinned validator, token/interface types and RangeState sources, using a controlled asynchronous token provider and monotonic test-content revisions. It runs outside every production worktree. [Source provenance](neon-provenance.json), [test](StaleRevisionTests.swift), [unmodified failure](neon-unmodified.log) and [post-await guard control](neon-post-await-guard.log) are retained here.

- Unmodified: request revision 0, live revision 1, one stale application, validation incorrectly reports success; both assertions fail.
- One added post-await revision check in the isolated copy: no application, validation reports stale; both assertions pass.

This proves the generic validator defect. It does **not** prove this caused the hosted Markdown mismatch, exercise real TextKit/tree-sitter state, or qualify a production dependency fix. Production checkouts and pins remain unchanged; no upstream submission occurred. The isolated archive also retains the initial manifest syntax error and compiler crash from omitting a generic closure argument; the final test supplies that closure explicitly. No test result is claimed from those unsuccessful compilation attempts.

To reproduce, create a new temporary Swift package containing copies of pinned Neon's `Sources/RangeState` and just `Token.swift`, `TokenSystemValidator.swift`, `TextSystemInterface.swift` in its `Neon` target. Add pinned Rearrange as a local path dependency, and the attached test in a target depending on Neon and RangeState. Use Swift tools 6.0, macOS `"26.0"`, and `swift test --no-parallel`. Preserve the failure before adding `guard range.version == currentVersion else { return .stale }` immediately after the asynchronous token-provider call and running the paired control. The full prepared package is in the CORTANA archive's `neon-revision-probe/` directory, with original source hashes and licence.

## Diagnostic change and stopping rule

The accompanying test-only change retains every original assertion, the 150 ms bounds, and both setup/idle variants. Cleanup logs monotonic phase timestamps spanning task dispatch, watchdog sleep and result delivery. Observer overhead stays inside the bound; a passing instrumented run does not disprove earlier failure. `timeoutGateCompleted` records return from an actor call and can appear after `gateWaitReturned`.

After a recorded styling mismatch, fixed observations at two seconds, then after explicit invalidation, then after reconstruction distinguish eventual completion, revalidation and parser-state recovery. The reference editor is also re-read; a settling reference must not be mistaken for persistent edited-editor corruption. These observations cannot erase the original failure and are not production recovery behavior.

Run one materially changed native CI diagnostic attempt after independent review and local compilation/lint. Preserve either outcome; do not rerun unchanged to obtain green. A green diagnostic attempt alone does not resolve either prior failure or allow the integration PR to merge. Keep #480 draft/master-blocked and #53/#203 open; existing Release performance failures and native/manual/release gates remain.

Local diagnostic validation: the first three-file patch passed both affected suites; after the independent review requested observation of the reference editor too, the final patch passed both targeted parameterized tests. Strict changed-file lint and format checks passed. Exact patch hashes, commands and results are attached. These successful local samples do not resolve the hosted failures. The read-only independent reviewer accepted one diagnostic CI attempt with those limits.
