# Observe highlighting after the reduced editor becomes idle

MostlyText can restore full highlighting after a large document shrinks, yet leave
some inline bold, italic, link, or raw-text styling different from a freshly opened
editor. The default-clock test failed on hosted CI at the combined candidate
`ad79f2773f2cbaf8bb78bdb796b1d11b411be79b`. This diagnostic collects evidence about
that failure without changing the production package, dependency pins, fallback
size, timing assertions, or release gates.

## Scope and method

The ordinary CI jobs run first. A separate hosted macOS VM then exports the actual
checked-out commit's `MacDown2/Packages` tree into a new temporary directory and
applies the two patches here. It resolves and audits all 22 locked dependencies
before applying the Neon patch to that temporary dependency checkout. The normal
checkout must remain unchanged. This is a separate execution, not a trace of the
ordinary CI process that ran earlier.

- `neon.patch` adds passive observations to the locked Neon revision
  `484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165`. It does not patch SwiftTreeSitter or
  modify any package requirement or deployment target.
- `package.patch` exposes the already-locked Neon product to the copied test target
  and registers only the two synthetic cases of
  `shrinkingBelowTheRestoreThresholdRestoresOnlyAfterIdle`. It retains the original
  clock, 100/300 ms pauses, edits, assertion evaluation order, and existing failure
  probes. The additional final style enumeration occurs after the original oracle.
- `MacDown2/scripts/restore-trace/collect.py` exports, audits, patches, builds and
  tests the copy. Its default is the full serial package suite. `--filter` is for
  a bounded local validation of the diagnostic itself.

The recorder assigns a session to each case, a role to each edited/fresh view,
and immutable UUIDs to clients and parser trees. Each restored or rebuilt client
gets a distinct identity and generation. Existing late callbacks remain attributed
to their original client. A task-local query number connects existing provider
calls to token applications without modifying token equality or adding tasks.

Observed events include storage edits and hashes, live/snapshot content limits,
query admission/version/results/application ranges and tokens, invalidation ranges
and the `sublayers` flag, validation actions and outcomes, both synchronous and
asynchronous sublayer paths, and parser operation submission, queue dispatch,
execution and completion. Input-edit metadata is recorded as numbers and points.
Rendered runs contain only ranges and font/color/underline signatures.

## Data and interpretation limits

Only explicitly registered synthetic fixtures are collected. No document text,
environment dump, credentials, network payload, or arbitrary file content belongs
in the trace. Content identity is a SHA-256 digest of UTF-8 text; sizes and editor
ranges use UTF-16 units. Error observations contain error types, not error messages.

Each case buffers at most 32,768 events and 16 MiB of event payload in memory. It
writes JSON only when the selected test and its existing failure probes finish.
Dropped-event and unfinished-observed-work fields must be inspected. The end of
collection is not proof that all asynchronous work drained. A timeout can produce
no trace because there is deliberately no live file writer. Event sequence is lock
append order; cross-thread causality requires the explicit operation/query IDs and
submission/dispatch/execution boundaries.

The added locks, hashing, UUID allocation, and observations can perturb scheduling.
A passing instrumented run does not resolve an earlier uninstrumented failure.
This experiment adds no holds, omissions, cancellation, manual clocks, extra task
joins, new sleeps, or new styling/invalidation actions. The existing diagnostic
failure probes still wait, invalidate, and rebuild exactly as in the candidate.

## Provenance and holds

The source package must equal candidate `ad79f2773f2cbaf8bb78bdb796b1d11b411be79b`.
Its lock hash is
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
The runner records the actual checkout SHA/tree, the PR head/base identity when
available, patch hashes, checkout revisions, tool versions, logs, command exit
statuses, and final source attestation. Collect the complete raw hosted job logs
and trace artifact; rendered log summaries can omit the test tail.

This branch is diagnostic only. It must not become a production dependency patch
or a release candidate. The 8,192 UTF-16 fallback and production pins remain in
place. PR #480 remains draft/unmerged; issues #53 and #203 remain open. Manual
Pinyin evidence retains its documented coverage limits; automated XCUITest did
not establish CJK coverage. Owner review and all release gates remain required.

## Local diagnostic validation

The original parameterized restore test ran once with the reviewed passive patches
at diagnostic source `d5114f66551e78ed5b7c87bf37a990870cfaf23e`. Both cases passed;
the two exact rendered-style oracles matched their fresh references. Their traces
contained 149 and 187 events, no dropped events and no unfinished observed work.
They do not assert quiescence and did not reproduce the historical hosted failure.
Independent inspection found only synthetic fixture metadata in the traces/logs.

The collection attempt itself remains recorded as failed: Swift's launcher changed
its command during `exec`, causing the runner to refuse helper admission. The test
exit code was 0, and source/lock/all 22 pin/post-patch hash checks passed. A later
read-only process inspection confirmed the test process and helpers were gone.
The runner correction preserves live child/start/parent identity across `exec` and
keeps exact helper birth/command/bundle checks before signals. A separate synthetic
exec-plus-detached-helper probe verified tracking, cleanup and exit; wrong-bundle,
non-child and changed-owner-start controls were refused. The product test was not
repeated to replace the retained collection outcome.

Two earlier setup failures were also retained: origin URL lookup initially missed
SwiftPM's local bare-repository indirection, and the new test support file initially
lacked its test-only import. Both stopped before tests executed, were corrected,
and received independent review. These are diagnostic setup failures, not evidence
about the product regression.

The hosted diagnostic is still required. It runs the full package suite on a
separate VM after ordinary CI and must retain its original result even if the trace
is incomplete or the style oracle fails.
