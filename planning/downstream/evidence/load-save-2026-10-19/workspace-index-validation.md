# Workspace index freshness validation

Base: `5b32f93cab98286356231d9e8bc7e02777ca731f` (`review/183-load-save-responsiveness`). The final source checksums are in `workspace-index-source.sha256`.

## Verification

The final locked-dependency app test invocation used Xcode 26.6, macOS 26.5.1, the existing `settings-protection-a4c48bc7-2026-10-19/DerivedData`, `-onlyUsePackageVersionsFromResolvedFile`, and `-enableCodeCoverage NO`:

```sh
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 \
  -destination 'platform=macOS' \
  -derivedDataPath /Users/jonathanlim/GitHub/_cleanup-archive/settings-protection-a4c48bc7-2026-10-19/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO \
  -only-testing:MacDown2Tests/WorkspaceIndexFreshnessTests \
  -only-testing:MacDown2Tests/WorkspaceIndexRefreshBehaviorTests \
  -only-testing:MacDown2Tests/WorkspaceIndexRootPublicationTests test
```

Result: **13 passed, 0 failed, 3 suites**. The `.xcresult` is at `/Users/jonathanlim/GitHub/_cleanup-archive/settings-protection-a4c48bc7-2026-10-19/DerivedData/Logs/Test/Test-MacDown2-2026.10.19_08-45-08-+0800.xcresult`. Full compiler and test stdout/stderr is retained at `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19/workspace-index-slice2-final-xcodebuild-verified.log`; its SHA-256 is in `workspace-index-validation.sha256`.

Strict SwiftLint, SwiftFormat lint and `git diff --check` passed on the six changed Swift files. Xcode emitted one dependency warning from cmark-gfm about `DEFINES_MODULE` without an umbrella header and two routine App Intents metadata-extraction notices. The changed Swift files produced no compiler warnings.

An earlier focused invocation failed during test-target compilation because a newly split test-support source file was not yet in the generated Xcode project. The project was regenerated with XcodeGen, the missing `@testable` import was corrected, and the final invocation above compiled and passed. That earlier result was a compile failure, not an assertion failure.

## Coverage

The app tests count real index walks to verify one initial walk followed by a throttled activation, forced refreshes and explicit mutations still walk, and a failed build does not earn freshness before a successful activation retry. Held detached walks cover same-root activation supersession, a late older initial completion, A → B → A identity, clearing and closing. A paused pre-root await verifies an activation refresh cannot use the old root while a new root request is active.

Fixtures use temporary roots/session state and unique `UserDefaults` suites; controller fixtures close the real window controller and retire private state. No package API, dependency or generated-project source change was made; the ignored Xcode project was regenerated from `project.yml` to discover added app-test files.
