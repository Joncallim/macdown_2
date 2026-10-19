# Save-conflict validation

Validation ran on branch `review/183-load-save-responsiveness`, base HEAD `5b32f93cab98286356231d9e8bc7e02777ca731f`.

## Final serial checks

| Command | Exit | Result |
|---|---:|---|
| `swift test --force-resolved-versions --filter 'WorkspaceConflictReadTests|WorkspaceTabSwitchSaveTests|WorkspaceModelSaveQueueTests|WorkspaceModelFileTests|WorkspaceModelFileSaveAsTests|TabStoreEncodingOpenTests'` | 0 | Retained final log confirms 36 tests in 6 suites passed. The implementation agent reported no compiler warnings, but the retained log contains test output only, so a reviewer cannot independently verify compiler-warning status. |
| `swiftlint lint --strict` on the four changed Swift files | 0 | 0 violations, 0 serious. |
| `swiftformat --lint` on the four changed Swift files | 0 | 0/4 files require formatting. |
| `git diff --check` | 0 | Clean. |

The final Swift test log is retained at `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19/final-workspace-suites.log`; its SHA-256 is in `final-workspace-suites-log.sha256`.

The focused `WorkspaceConflictReadTests` run was also reported as passing before mutation testing: 6 test functions and 18 parameter cases. The implementation agent reported a successful build, but raw compiler output for this focused run was not retained for independent verification. A first launch without escalation was blocked while SwiftPM invoked `sandbox_apply` (`Operation not permitted`); the same command was reported to succeed when rerun with execution approval. This was an environment launch failure, not a compile or assertion failure.

## Controlled mutation controls

The implementation agent reported that each mutant compiled and failed on the intended assertion. Raw compiler and assertion outputs were not retained, so reviewers cannot independently verify those compile/failure outcomes from the current evidence. The final retained test log independently confirms the unmutated suite outcomes, and the source hash artifacts identify the tested/restored source versions. The reviewed source was reported restored from the archived copy after each control; the restored `WorkspaceModel+SaveConflict.swift` hash is `3e10f7757983cd4bcf9c8f5e7c621b0c2a4d0cd46cb65ab257029d6446b5397b`, matching `mutation-source-before.sha256`.

| Mutation | Test command | Exit | Rejected behavior |
|---|---|---:|---|
| Remove all three `isLatestSave(context)` guards | `swift test --force-resolved-versions --filter WorkspaceConflictReadTests` | 1 | Newer failed-save error and document/disk state were overwritten. The assertion reported the newer ASCII-encoding error replaced by unresolved conflict, and the old save wrote `local café` to disk. |
| Admit a dirty document despite changed conflict baseline | `swift test --force-resolved-versions --filter WorkspaceConflictReadTests/anObsoleteReadCannotReplaceANewerOutcome` | 1 | The `reload then type` case changed from dirty to conflict and replaced its `noActiveDocument` error with unresolved conflict. |
| Remove post-recovery-persistence ownership guard | `swift test --force-resolved-versions --filter WorkspaceConflictReadTests/newerOutcomesAfterRecoveryPersistenceKeepTheirOwnError` | 1 | Newer typing, save, and close/reopen outcomes each lost their own error to the old conflict completion. |

These are intentional controlled mutations, not runs against the untouched reviewed source. The behaviors and assertion failures in the table are the implementation agent's reported findings; raw command output is unavailable for independent confirmation. Mutated file hashes are recorded in `mutation-1-latest-guards.sha256`, `mutation-2-dirty-baseline.sha256`, and `mutation-3-postpersist-guard.sha256`. Exact reviewed Swift source hashes are in `final-source.sha256`. Copies of the reviewed implementation and regression file are retained in the archive directory above.

No Xcode, app-target, performance, signing, network or external-service commands were run for this save-conflict validation. The separate workspace-index slice has its own Xcode app-target evidence in `workspace-index-validation.md`. The source and regression changes remain uncommitted for independent review.
