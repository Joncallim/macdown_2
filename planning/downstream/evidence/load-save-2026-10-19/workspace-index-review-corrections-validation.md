# Workspace index review corrections validation

Base: `5b32f93cab98286356231d9e8bc7e02777ca731f` on `review/183-load-save-responsiveness`. This report records the corrected source separately from the earlier 13-test result in `workspace-index-validation.md`; it does not replace that historical evidence. Final source SHA-256 values are in `workspace-index-review-corrections-source.sha256`.

## Changes validated

The refresh guard now follows the current root request's tree-application phase instead of permanently comparing against its original URL. Once that request applies the root, refresh captures the current actual access root, so an accepted folder remap remains refreshable. Root request and build identities still guard every await, and ordinary refreshes publish folder-search scope only for a matching pending explicit request. The added accepted-remap test exercises the coordinator's actual move-remap path without changing existing folder-search remap behavior.

Held walks now have separate gates by invocation. Failure paths release and join held operations before assertions can throw. The mutation test waits for the index walk to complete and for the created path to be published. Fixtures remove controllers and close the real window controller; the close regression performs that lifecycle while a walk is held.

The load path also moves the loaded-text NUL trigger scan into the detached `document.load()` closure and returns its Boolean alongside the loaded document. Explicit encoding still skips this scan and the existing automatic-detection tests cover that behavior. The slice contract was updated to state this boundary.

## Validation

The final focused, locked app invocation used Xcode 26.6, macOS 26.5.1, the existing DerivedData location, `-onlyUsePackageVersionsFromResolvedFile`, and `-enableCodeCoverage NO`. It passed **14 tests in 3 suites**: `WorkspaceIndexFreshnessTests`, `WorkspaceIndexRefreshBehaviorTests`, and `WorkspaceIndexRootPublicationTests`. The `.xcresult` is `/Users/jonathanlim/GitHub/_cleanup-archive/settings-protection-a4c48bc7-2026-10-19/DerivedData/Logs/Test/Test-MacDown2-2026.10.19_13-22-24-+0800.xcresult`. Complete stdout/stderr is `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19/workspace-index-review-corrections-final2-xcodebuild.log`.

The locked MacDownKit run used `swift test --force-resolved-versions --filter TabStoreEncodingOpenTests --filter TabStoreCoreTests` and passed **19 tests in 2 suites**. Complete stdout/stderr is `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19/workspace-loadscan-package-tests-escalated.log`.

Strict SwiftLint passed with 0 violations and SwiftFormat lint passed with 0 files requiring formatting across the seven changed Swift files. `git diff --check` exited 0. The lint, format, and test log hashes are in `workspace-index-review-corrections-log-hashes.sha256`.

Initial default-sandbox Xcode and SwiftPM invocations stopped during package/manifest resolution with `sandbox_apply: Operation not permitted`; neither reached compilation or assertions. The same locked invocations succeeded with the authorized escalated launch. Those failed initial logs are retained separately in the archive and included in the log-hash file.

Xcode reported the existing cmark-gfm module-map warning, routine App Intents metadata-extraction notices, and a runtime AppKit table-view reentrancy warning during tests. The changed Swift sources emitted no compiler warnings. The test suites passed despite those environment/framework warnings.

These are focused checks of the current source set, not a full package or whole-app suite and not final combined-candidate/release validation. No dependency pins or project-generation inputs changed.
