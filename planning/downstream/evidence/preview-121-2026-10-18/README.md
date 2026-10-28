# HTML preview callback ownership checkpoint

Older HTML navigation callbacks can no longer mark a newer preview as complete
or consume its retry state. Recovery also respects a queued retry of the same
saved revision and remains available after a newer queued save is cancelled by
an edit. This is an app-coordinator correction within #121, not completion of its
resource-authority or cancellation contract.

The validated source candidate is **a293e39719dc2891abd0354bfaa2c64c130c7185**,
on CORTANA, 2026-10-18 UTC, macOS 26.5.1, Xcode 26.6, Swift 6.3.3. It follows
baseline `a4c48bc72955db21bdd8546c0e97bff051093216`. The subsequent evidence
commit changes documentation only; source/tree identities and actual invocation
heads remain explicit in [validation.json](validation.json).

## What establishes the correction

The exact baseline coordinator was compiled into an isolated diagnostic with
ordered callbacks and valid WebKit-issued navigation objects. Starting A then B,
then reporting A's late finish, incorrectly marked B complete and prevented its
retry after a real failure. A separate late failure incorrectly cleared B's
pending state. This is deterministic callback-order evidence, not a claim that
WebKit always emits that ordering.

The correction keeps the returned navigation, originating view and saved
generation together. Only that exact callback may complete or fail the attempt.
Queued work has its own identifier, separate from the displayed page and its
one-reload process-recovery budget. Disposal revokes callback ownership before
stopping WebKit. No package API or dependency changed.

Independent review found two additional schedules before final validation:

- A failed revision queues a retry; process recovery must not complete that
  queued attempt's admission before it starts.
- A save queues a newer revision, then an edit cancels it; the displayed page
  must still be allowed its existing process recovery.

Both schedules first failed retained regressions, then passed after their
corrections. Removing the navigation/view identity checks only in a source copy
also makes stale-success, failure and retry assertions fail. Fixtures obtain
valid navigation tokens from local blank pages and manually inject the tested
callbacks; they do not prove hostile-resource containment or native scheduling.

## Validation and limits

| Check | Outcome and scope |
| --- | --- |
| Strict lint and format | Pass on a293e397. The earlier committed candidate's two layout violations are preserved. |
| Affected HTML preview and contained-reader package checks | Debug and Release pass with locked dependencies. No full-suite or performance rerun. |
| Source compliance | Pass from the committed source archive. |
| Release compliance | **Fail: eight existing release findings remain.** Exit 1 is retained, not treated as approval. |
| Unsigned Release app and CLI | Build invocations pass. App-owned Swift compilation retains warnings-as-errors and optimization. |
| Release app and UI test targets | Pass in fresh TestDerivedData with optimization and testability enabled, and code coverage disabled. Compilation is not UI test execution. |
| Isolated selected app tests | Pass on optimized candidate source with retained Release objects and explicit profiling runtime. Real coordinator source and tests are compiled together, removing only the app test import. No product AppDelegate is launched. |
| Real WebKit main-document control | Pass: the rendered-marker page completed through the real handler. This proves a simple local page reaches the rendered marker through the real handler; it does not prove the hostile corpus, network denial, window behavior or crash scheduling. |
| Dependency provenance | All 22 SwiftPM and 22 Xcode checkouts are clean and match the production lock. Production pins and the 8,192 UTF-16 fallback are unchanged. |

Heavy commands ran serially. No product preference values or user documents were
read or changed. No full app/UI walkthrough, minimum-macOS-26.0 run, performance
claim or signed-artifact proof is supplied by this slice.

## Retained failures and artifact attribution

The first diagnostic attempts encountered module-map/include and actor-isolation
compiler errors. A subsequent fixture constructed `WKNavigation` directly and
crashed during its deallocation. Those attempts are retained, including the crash
report. The corrected fixtures obtain navigation objects from WebKit; the baseline
observations were replayed with those valid objects. Earlier failed fixtures are
not counted as passing evidence.

The first committed-candidate lint run rejected excessive nesting and the test
type length. A source-layout-only commit corrected both. Test compilation then
exposed distinct validation configuration failures, all retained with commands,
timestamps and hashes:

1. Omission of CI's documented `-enableCodeCoverage NO` caused the known pure-C
   package `___llvm_profile_runtime` linker failure.
2. Existing `@testable import FileCore` required a testable Release module.
3. After enabling testability, compiler commands produced a testable framework
   module, but Xcode still selected an older non-testable standalone module in
   the shared build directory. Different hashes and modification times are
   recorded; the original directory was preserved and a fresh test directory
   used to test that specific diagnosis.

The original plain Release app/CLI invocations and subsequent test-build
configurations remain distinct. The standalone harness also initially failed to
link profiling-instrumented retained objects. Its corrected invocation explicitly
links the profiling runtime and writes profiling output only into the evidence
directory. This is correctness evidence, not a timing measurement. Later builds can replace artifacts in shared
DerivedData. Recorded final hashes explicitly identify their current directory
and configuration; they are not silently attributed to earlier build commands.
The selected standalone runtime checks use optimized source and retained
candidate Release package objects from mixed diagnostic stages, some with
testability enabled. Each actual linked object is hashed in the runtime record;
these are not pristine original app-build bytes or fresh test-directory objects. Build-tool diagnostics remain in the logs;
this is not a claim that the whole tool chain is warning-free. In particular,
AppIntents metadata extraction, cmark module-map generation and dependency-scan
warnings remain recorded in the successful test-build log. Some named direct
dependencies are already declared in Package.swift (for example TextSearch →
FileCore); this observation does not establish a cause or dismiss the remaining
diagnostics. Their reconciliation remains a build/release gate.

## Remaining gates and recommended next action

The baseline probe separately reproduced two still-open #121 failures: a delayed
A resource request receives the sentinel from root B after the mutable request
is replaced; a task stopped during response delivery still receives data and
finish. These synthetic controls are not native exploit or network observations.
This patch does not change the scheme handler. Immutable per-load context/root
identity, Save As and document-lifetime identity, bounded off-main reads, worker
and payload ownership, stop-aware delivery, scope balancing and the full native
hostile-content corpus remain required. The same-generation dirty-debounce gate
policy is also deferred; normal edit/save transitions advance generation.

Next, reconcile the immutable-context and task-registry slice with the accepted
#121 architecture using the retained root-confusion and stop-delivery controls.
Do not add another reader or infer a directory grant. #121 remains open, and
independent source review does not replace owner acceptance.

The #53 protected shared-writer/admission/recovery gaps remain untouched. #203
remains open: parser **484.814584 ms / 400 ms** and editing-assist
**56.881709 ms / 50 ms** remain failed and unexplained. No performance suite was
rerun without a new causal hypothesis. Original hosted timing/rendered-run
failures, limited Debug-only Simplified Pinyin evidence, unproved automated CJK
coverage, eight release-compliance findings and all release holds remain.
Experimental dependencies remain isolated and unadopted. No hosted result covers
this candidate.

Nothing was pushed, merged, deployed, signed, notarised, submitted upstream or
changed in an external issue. No unique work was deleted. Source review and final
evidence disposition are recorded separately in [INDEPENDENT_REVIEW.md](INDEPENDENT_REVIEW.md).

Raw evidence, including all failed invocations and copied-source controls, is
retained at
`/Users/jonathanlim/GitHub/_cleanup-archive/preview-121-a4c48bc7-2026-10-18/`.
The [manifest](evidence-manifest.json) binds those supporting files by hash.
