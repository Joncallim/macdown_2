# Keep HTML preview callbacks attached to their originating navigation

## Owner outcome and scope

A late completion from an older HTML load must not mark a newer load as rendered
or prevent its retry after a real failure. This bounded correction records the
navigation returned by WebKit together with its view and generation, and accepts
only callbacks belonging to that attempt. The default debounce, saved-only
preview policy, crash-reload budget and security policy stay in force.

This is one part of #121. It does not fix the independently reproduced scheme
handler root confusion or post-stop delivery, integrate the contained reader,
or establish real WebKit hostile-content/network behavior. Those remain release
blockers under the [accepted handoff](issue-121-handoff.md). The #53 shared writer
and recovery architecture is unrelated and remains unchanged.

## Baseline and reconciliation

The inspected clean integration baseline is
`a4c48bc72955db21bdd8546c0e97bff051093216`; live local master is
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. The live #121 body and both comments
were read, together with EPIC_STANDARD, RELEASE_HARDENING and the readiness
review. The only coordinator difference from master before this slice is the
existing main-document error classifier and its regression.

The older handoff has two stale implementation assumptions. Explicit MIME/CSP
headers and `HTMLPreviewContentTypeTests` now exist, as does the real
`HTMLPreviewRenderTests` main-document control. `LocalResourceAccess` already
implements the synchronous stage-A constrained reader. Its historical native
probe and reader tests do not establish the planned off-main executor, aggregate
quotas, payload retention or minimum-macOS-26.0 proof. Do not rebuild that core
or treat it as a complete asynchronous resource service.

## Deterministic reproduction

The baseline diagnostic compiles exact copied coordinator, scheme-handler and
reload-budget source. A same-file fixture extension exposes admission and
begin-load operations without rewriting production logic. A recorded WKWebView
obtains distinct actual WKNavigation objects from local blank pages; the probe manually orders delegate
callbacks. This proves coordinator behavior for that schedule, not the order in
which real WebKit necessarily emits callbacks.

1. Admit/start A at generation 7, then B at generation 9.
2. Deliver A's late finish. Baseline incorrectly records B as loaded.
3. Deliver B's real timeout. Its pending state has already disappeared, so B
   cannot retry. A separate late-A-failure case incorrectly clears B's admission.

Two separate baseline observations are retained: a delayed A scheme task receives
the sentinel from temporary root B after request replacement; a recording task
that calls stop during response delivery still receives data and finish. The
second is a synthetic reentrancy control, not a native WebKit observation.

## State, ownership and correction

The app coordinator owns one optional pending navigation record containing its
WKNavigation object, originating view identity and captured generation. It also
retains only the current page generation and a weak view reference for process
recovery. No navigation history accumulates. Package reload-gate APIs and module
dependencies do not change; the gate is readable within the app module for tests.

`beginLoad` revokes the older navigation record before starting a replacement.
The returned navigation installs the new record. A nil return rearms only its
captured generation through the existing generation-aware gate. Success and both
failure delegates require the exact non-nil navigation and view. A matching
terminal callback consumes ownership once; unknown, duplicate, stale and disposed
callbacks cannot consume another attempt. Existing cancellation/error URL
classification remains intact.

Debounced admission and active navigation are separate lifetimes. Each scheduled
attempt has a UUID that is checked after debounce and cleared before begin-load,
on cancellation and on disposal. Process termination skips recovery while any
attempt is queued, including a retry of the same generation. A generation-only
guard failed the independent reviewer’s deterministic control: failed A(g), queued
retry B(g), recovery R(g) finishing before B starts, then B failing. R incorrectly
consumed B’s admission and prevented another retry. The scheduled-attempt guard
closes that demonstrated race. Recovery does not infer scheduled ownership from
the reload gate: a normal save followed by an edit can cancel a queued revision
while leaving its gate generation pending. A retained regression proves that the
displayed page can still use its recovery budget after that cancellation, without
claiming the cancelled revision rendered. Otherwise
the recovery navigation receives its own identity, using the current page's
generation, without resetting the one-reload budget. Disposal invalidates all
navigation/page ownership before calling stopLoading and releasing the existing
scope. This patch does not redesign scope or worker lifetimes.

The existing completed-page recovery policy is unchanged: after an already
completed page's process recovery fails, there is no new saved-generation
admission to rearm. A subsequent document update remains necessary. Tests of
recovery failure/nil returns cover an outstanding pending generation, not a new
automatic retry policy after completed-page failure.

## Verification and stop conditions

`HTMLPreviewNavigationIdentityTests` invokes the real coordinator with a recorded
web view and explicitly ordered callbacks. Fixtures use a zero debounce delay
and bounded suspension while awaiting load entry; no elapsed-time assertion is
used as correctness proof. Cases cover late success and both failure delegates,
retry after a real failure, nil/unknown/wrong-view callbacks, disposal reentrancy,
queued-newer and same-generation retry admission, recovery after a queued revision
is cancelled by an edit, process-reload identity/budget, nil load/reload, and old
recovery callbacks after a newer load starts. Production construction and the
native render control keep the default 150 ms delay. The fixture loads only local blank HTML without a navigation
delegate to obtain valid WebKit tokens; all tested callbacks are explicitly
injected. No product preferences or user documents are needed. Direct
WKNavigation initialization was rejected after a retained deallocation crash;
that failed fixture run is not passing evidence.

Require independent source/evidence review, a negative control removing identity
matching, affected Preview/LocalResourceAccess checks, app-test compilation,
isolated selected app tests, strict lint/format and unsigned Release app/CLI
builds on the committed candidate. Record native render control separately from
synthetic delegate tests. Preserve first failures and exact source identities.
No benchmark rerun or threshold change is justified by this callback-only fix.

Stop before changing resource grants, asynchronous I/O admission, worker/buffer
settlement, parser/rendering dependencies or settings persistence. These require
the broader accepted architecture and their own fixtures. The same-generation
dirty-debounce cancellation gap is also deferred: normal FileDocument edit/save
transitions advance generation, so a synthetic public-state sequence alone is
not a demonstrated normal-save wedge.

There are no new UI strings, accessibility controls, export changes or authored
text transformations. Source/rendered switching, the hostile resource corpus,
scope balancing under real loads and final Release dogfood remain required for
#121 closure; this delegate correction does not satisfy them by itself.
