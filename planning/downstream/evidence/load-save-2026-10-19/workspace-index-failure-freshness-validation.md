# Workspace index failure freshness validation

Base: `5b32f93cab98286356231d9e8bc7e02777ca731f` on `review/183-load-save-responsiveness`. This is the latest focused index validation; earlier index reports and source snapshots are preserved as historical evidence. Current source hashes are in `workspace-index-failure-freshness-source.sha256`.

## Correction and regression

A successful walk previously remained eligible for activation throttling after a later forced refresh failed. Since `WorkspaceFileIndex` drops its paths and enters `.failed` on failure, restoring access and activating within the throttle interval could leave an empty index in place. After the current root-request, build, open-window and actual-root guards, terminal non-ready outcomes now clear the saved freshness timestamp, root, and request generation. An older superseded completion returns before this invalidation, so it cannot clear a newer success.

The new real-root regression completes an initial successful walk, makes the actual directory unreadable for the second forced walk, verifies the current freshness record is cleared, restores access, and immediately invokes a 60-second-throttled activation. The third walk runs and republishes the file path. The walk probe's failure is tied to invocation two; existing initial-failure coverage remains unchanged.

## Validation

The final locked app run used Xcode 26.6, macOS 26.5.1, existing DerivedData, `-onlyUsePackageVersionsFromResolvedFile`, and `-enableCodeCoverage NO`. It passed **15 tests in 3 suites**: `WorkspaceIndexFreshnessTests`, `WorkspaceIndexRefreshBehaviorTests`, and `WorkspaceIndexRootPublicationTests`. Full stdout/stderr is `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19/workspace-index-failure-freshness-xcodebuild.log`; the `.xcresult` is `/Users/jonathanlim/GitHub/_cleanup-archive/settings-protection-a4c48bc7-2026-10-19/DerivedData/Logs/Test/Test-MacDown2-2026.10.19_13-27-14-+0800.xcresult`.

Strict SwiftLint passed with zero violations and SwiftFormat lint passed with zero files requiring formatting across seven changed Swift files. `git diff --check` exited 0. Log SHA-256 values are in `workspace-index-failure-freshness-log-hashes.sha256`.

The focused MacDownKit encoding-open and core suites passed 19 tests in 2 suites on the same source set before this final app-only index correction; the package source did not change in this correction. The exact locked run and log hash remain in the preceding [review-corrections report](workspace-index-review-corrections-validation.md).

Xcode emitted the previously observed cmark-gfm module-map and routine App Intents metadata notices, plus AppKit table-view reentrancy warnings during app tests. The changed sources emitted no compiler warnings. This is focused validation, not a whole-app or whole-package suite, independent review, or actual combined Release validation. No dependency pins or generated-project inputs changed.
