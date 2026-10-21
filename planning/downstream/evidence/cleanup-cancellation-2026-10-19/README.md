# Keep fixture cancellation from blocking its watchdog

## Owner summary

This correction keeps a test fixture's slow cancellation callback from occupying
the Swift executor needed to enforce its cleanup timeout. It changes test
support only; editing, document content, production text filters, highlighting
policy and dependency pins are unchanged. The original 25 ms timeout and 150 ms
regression bounds remain. It fixes a reproduced cancellation-isolation defect,
not the still-unexplained hosted late-sleep failure.

## Contract and reproduced defect

The baseline is combined candidate dbf0374ed71b103bac4f790d3bbd6556702ee9e7.
Fixture setup is outside the cleanup interval. One absolute monotonic deadline
starts immediately before cancellation dispatch; callbacks and scheduling
consume that interval. The first acknowledged completion/timeout result still
wins. Timeout does not terminate a synchronous callback or permit deletion of
resources it may still use. There is no hard real-time scheduler guarantee.

The helper previously invoked each synchronous cancellation callback inside its
TaskOwner actor. Task.detached did not move that actor work off Swift's
cooperative executor. With LIBDISPATCH_COOPERATIVE_POOL_STRICT=1, both existing
blocking-cancellation cases failed the unchanged bounds: cleanup took
205.281125 / 205.226083 ms, and the watchdog did not start until cancellation
returned at approximately 205 ms. The new held-cancellation regression also
failed on the unchanged helper under ordinary scheduling: obtaining the task
handle occupied the owner until the two-second barrier's deadlock guard expired.
That guard is not a replacement for the 150 ms requirement.

The first diagnostic invocation mistakenly used the ineffective
SWIFT_CONCURRENCY_COOPERATIVE_POOL_STRICT variable. Its passing result is
retained locally and excluded from constrained-executor evidence. The corrected
LIBDISPATCH invocation above is the first effective constrained test.

## Smallest correction and ownership

Registration closes and one aggregate task is cached without suspension. That
task sends one serial loop of cancellation callbacks to a regular Dispatch
queue, then starts the existing concurrent joins only after every callback has
returned. Separate owners do not share a serial cancellation queue. All callers
receive the same aggregate task, including its cancellation phase. Cancelling
that task does not skip resource cancellation; its eventual joins inherit
cancellation. A callback that never returns still owns its resources; this
change does not make arbitrary blocking work stoppable.

Obtaining the task handle no longer means callbacks have finished. The test-only
phase marker is therefore renamed from cancellationReturned to
cleanupTaskAcquired. Historical timeline labels retain their old meaning.
Direct callers await the aggregate or explicit progress, so the handle-return
change does not authorize early directory removal.

Independent review also found that the blocking deadline test removed its
directory after a nonfatal failed completion-signal assertion. It now retains
the owner and awaits the actual aggregate, preserving the directory if the
cleanup report is unresolved. The new timeout-during-cancellation regression
holds a callback, observes timeout with the directory retained, then releases
and joins actual work before removal.

## Regression and validation evidence

The three attached logs preserve the corrected constrained baseline failure,
the new ordinary-scheduling regression failure on the old helper, and the first
constrained pass after the correction. The corrected helper returned cleanup in
27.732125 / 25.574209 ms. The new tests cover responsive closed registration,
exactly-once ordered cancellation, cancellation before every join, timeout
propagation into an eventual join and retained directory lifetime. Final review
added direct equality of both returned Task handles to detect a falsely
completed second task, even if callback counts were unchanged.

The affected TextFilters module passed under normal scheduling before that
last assertion addition; strict repository lint/format passed. Final frozen-head
Debug/Release and constrained validation are pending at this documentation
checkpoint. Completed results must identify the final head and source hashes;
consult PR #493 and the retained CORTANA archive for subsequent validation and
independent review:
/Users/jonathanlim/GitHub/_cleanup-archive/watchdog-contract-dbf0374e-2026-10-19/.
The attached first-pass logs are not mislabeled as those final-head runs.

Heavy builds run serially; package resolution remains forced to the lock.
No unchanged hosted retry or new diagnostic PR/worktree is part of this fix.

## What remains unproved

[Hosted run 39266780519](https://github.com/Joncallim/macdown_2/actions/runs/39266780519)
failed at 165.163833 ms with a different signature: the watchdog started within
0.083 ms but returned from sleep at 165.066417 ms. The constrained cancellation
failure does not establish that hosted cause. Timer tolerance remains unchanged;
prior explicit-zero-tolerance diagnostics still returned over 100 ms late.
No universal bound for runtime scheduling, other deliberately blocking test
bodies or product cleanup is inferred.

The restored-style mismatch, native/IME coverage limits, seven strict compliance
findings, Release performance/acceptance gates and owner review remain open.
#492/#473/#474 were administratively superseded by #493 with original refs and
unique evidence retained; their closure does not close #159 or #173. Keep
#462/#493/#480 for their distinct review roles and #53/#203 open.
