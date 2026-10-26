# Complete hosted proposal for final review

No branch, workflow or source change has been published. No natural Swift experiment or local full build ran. The staged `hosted-package/` tree is an inspectable proposed repository payload, not another source checkout or build cache. Its workflow goes at `.github/workflows/neon-ordering-532.yml`; its scripts/patches go at `diagnostics/neon-ordering-532/`.

## Workflow and setup

The workflow triggers only a push to `diagnostic/532-neon-natural-ordering-2026-10-26` with its diagnostic paths changed. It has no workflow_dispatch/default-branch registration dependency, no pull-request trigger, no secrets inputs and no expanded permissions. Global contents:read, both checkouts persist-credentials:false. It checks out the diagnostic payload at the triggering commit and product source at exact #532 `f5605d9aead306e15ccb1bd8fb4f48b8931c1f76` into separate disposable hosted paths.

DEVELOPER_DIR selects the already-installed Xcode_26.0.1.app for this job only; both workflow and setup/harness assert Xcode 26.0.1, build 17A400. Missing toolchain fails; no install or system xcode-select change occurs. Job ceiling is 30 minutes. Helper tests have a one-minute step bound; dependency preparation six minutes; compile/test step fifteen minutes, plus two-minute always-upload budget.

Dependency preparation is now implemented: a new hosted scratch path, committed lock SHA check, one bounded `swift package --force-resolved-versions resolve`, unchanged-lock verification and all 23 effective workspace/checkouts validated against `natural-Package.resolved`. This is a network-enabled setup operation for public pinned repositories. Neither the flag nor cache presence is an offline guarantee; subsequent SwiftPM work could contact repositories, but it must retain the exact revisions, paths and patch hashes. There is no hidden source clone, pin update or extra product compile in the harness.

The natural experiment remains one compile, then exactly one named ungated test. No test after compile failure, no retry, no full-suite escalation. The existing eight GiB reserve and conservative four GiB footprint budget remain. All state changes occur only in disposable hosted repo/dependency checkouts after apply checks; no source scheduling correction is included.

## Provenance and instrumented verdict

`provenance.py` validates actual SwiftPM workspace-state remote identities, canonical URLs, revisions, checkout HEADs and checkout paths before patching and after compile/test. It hashes all patched Neon/app files before compilation and verifies every hash afterward and on failure. After successful compile it parses the actual SwiftPM description.json: exactly one compiler command each for RangeState, TreeSitterClient, Neon, Highlighting and HighlightingTests; Neon sources must all resolve inside the patched directory; patched source paths must occur in both sources and compiler inputs; compiled objects must exist. An alternate Neon directory or reverted patch fails the experiment.

Metadata records event and actual product/diagnostic commit identities, all 23 resolved pins/paths, lock and patch hashes, selected Swift executable/version, and a hash of the actual build description plus targeted compiler input paths. Root local packages remain bound to the exact product commit.

Success additionally requires the exact named Swift Testing start, a one-test result and two distinct fixture identities, each with correlated NEON_ORDER mutation enqueue, linked background request and callback from the same client. NEON_FIXTURE alone cannot produce an instrumented verdict. Ring eviction/incomplete correlation fails evidence sufficiency rather than being inferred as success. Local 26.6 tests do not clear hosted 26.0.1 CI; an instrumented natural pass still means only not reproduced.

Correlation also requires a worker execution in a distinct processor/operation and a RangeProcessor compare event whose expected version matches the enqueue version. The strengthened correlation test was rerun alone and passed (`helper-correlation-updated.log`).

## Crash ownership and caps

Fixture markers now include base64 process identity with PID and fixture UUID. `.ips` parsing examines the top-level final crash body only, requiring integer pid and procName. Nested thread/other-process pid fields do not establish ownership. Legacy `.crash` parsing requires a unique Process header in the header region. Both PID and process name must match an observed fixture. No fuzzy name matching is used.

Collection rejects symlinks and special files with lstat, O_NOFOLLOW/O_NONBLOCK and fstat. Reads stop at one MiB; oversized/stale/unreadable/unowned/skipped reports are counted. Scans have a three-second grace, 256 eligible-entry bound and explicit exhaustion reason. At most eight crash files; total artifact payload stays below eight MiB including capped logs and a 64 KiB metadata reserve. Only fresh PID-and-identity-correlated user DiagnosticReports are copied. No environment dump, source text, personal document or unrelated report is uploaded.

The workflow's upload runs on always(), has a two-minute ceiling and seven-day retention. Preparation/experiment failures remain nonzero. Earlier-stage toolchain evidence exists even if later setup fails; detailed preparation or natural metadata is retained when those stages begin. No continue-on-error is used.

## Lightweight local checks actually run

Thirteen distinct Python helper tests passed across the retained runs: top-level ownership/malformed report handling, process-name matching, symlink/FIFO/oversize rejection, explicit scan exhaustion, marker-only rejection, client/mutation correlation, workspace path redirection, actual compiler-input root/patch survival, normal success/nonzero status, TERM-resistant closed-pipe child, direct-child exit with descendant-held pipe, escaped descendant pipe deadline, and log overflow (some assertions share one test function).

The first helper run passed 11 tests in 19.849 seconds (`helper-tests.log`). The subsequent log-overflow test passed, but the added build-input fixture failed because its temporary /var path had not been canonicalized to /private/var (`helper-provenance-tests.log`). That deterministic fixture error was corrected with resolve(); only the corrected test was rerun, passing in 0.005 seconds (`helper-provenance-corrected.log`). All historical results are preserved. No flaky retry or natural-run retry occurred.

YAML parsing and read-only permission/job-ceiling checks passed using the installed Ruby YAML library. These are local structural checks, not proof GitHub accepted or executed the workflow. Python helpers passed on local Python 3.15; the hosted job must rerun them before setup. No Swift build was started during this packaging task.

Final independent review should inspect the full staged tree, especially locked setup arguments, build-input provenance schema assumptions, identity parsing and watchdog bounds, before any publication or hosted execution is authorized.
