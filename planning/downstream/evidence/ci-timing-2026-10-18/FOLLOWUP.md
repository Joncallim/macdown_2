# Window lifetime, deadline and compiler review

## Owner summary

The long window-close test delay has a reproduced cause and a bounded repair:
the preceding cache benchmark left its real window, parse work and observers
alive. Retiring that fixture removes the delay in both a controlled comparison
and the full app-target run. The cleanup regression again enforces its original
150 ms whole-call limit; the earlier cleanup-only measurement was too narrow.
Six UI suites and two status-view test suites now use their required main actor.

**This candidate is not ready for integration approval.** Its second planned
Release performance run failed a 400 ms parser ceiling at **484.814584 ms**.
That failure remains open. A later bounded diagnostic also failed the 50 ms
editing-assist ceiling at 56.881709 ms. Separate source review found no concrete
regression, with explicit coverage limits. Hosted cleanup failures, the original
highlighting run mismatch, runtime diagnostics, native interaction and owner/
release acceptance remain separate gates. No threshold, production pin,
test assertion or 8,192 UTF-16 highlighting cutoff was relaxed.

These changes improve test ownership and the reliability of verification. They
add no editor-visible capability or demonstrated typing-speed improvement. The
existing fallback still reduces highlighting for larger Markdown documents, and
the previously integrated repaint correction remains present.

## Exact source and validation identities

- Base: `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`, the current remote
  `integration-final` and draft PR #480 head.
- `985827858a3672e21617b35fc0c955563832034c`: benchmark retirement, isolated
  fixture settings/session storage, original whole-call cleanup assertion.
- `95c3d25f8adb44aba709f2818400cb90941d2a7e`: asynchronous XCTest lifecycle
  hooks in six UI suites; the tab suite explicitly uses `@MainActor`.
- **Final code: `0b85e6f09dc3bba82a0da3b15f1583b3263fcb74`**: also isolates
  the two status-view test suites to the main actor. All final build commands
  checked this exact head and a clean tracked worktree before and after.
- The package subtree, app sources, CLI sources and XcodeGen specification are
  byte-identical between `95c3d25f` and `0b85e6f0`. Their Git object IDs are in
  the machine record. The later change touches two app-test annotations only.
  Package results retain their actual `95c3d25f` provenance.
- CORTANA: M3 Pro, macOS 26.5.1, Xcode 26.6, Swift 6.3.3. Heavy commands ran
  serially. All 22 Xcode package checkouts matched the unchanged committed lock
  and were clean. Package and Xcode commands enforced the lock.

The [machine record](followup-validation.json) contains commands, timestamps,
outcomes, source equivalence and raw-evidence hashes. Raw material is retained at
`/Users/jonathanlim/GitHub/_cleanup-archive/astra-followup-272933c4-2026-10-18/`.
The earlier [validation](VALIDATION.md) remains historical evidence, not a result
for this later code. Subsequent documentation commits do not relabel executions.

## Corrections supported by negative controls

### Preserve the actual cleanup contract

The initial change in `90402ea5` measured only the interval after the fixture
body returned. Although its numeric limit stayed at 150 ms, that dropped the
old zero-delay test's call-to-result guarantee. The fresh author review caught
this weakening; `98582785` restores the original whole-call assertion. It also
avoids a newly introduced zero-duration suspension and records setup and cleanup
intervals separately. Both the zero-delay and deliberately slow-setup cases
still enforce the cleanup interval, including blocking cancellation dispatch.

A temporary 200 ms pre-body delay fails the restored whole-call assertion at
235.71525 ms, with 206.1805 ms in setup and 29.53475 ms in cleanup. Thus fast
cleanup cannot hide slow setup. The earlier mutation that moved blocking
cancellation outside the watchdog still supplies complementary negative
evidence: both cases failed at approximately 206/204 ms. Mutation sources were
restored byte for byte. An initial diagnostic-message compilation error is
preserved separately and was corrected before the probe executed.

The 25 ms watchdog and 150 ms test limit are unchanged. This is a test-fixture
failure-reporting contract, not the production text-filter subprocess timeout.
The full hosted logs lack phase timestamps: they do not establish whether setup,
scheduling or cleanup caused the recorded 160.1835/176.18825 ms overruns. The
correction preserves detection and adds diagnosis; it does not claim to fix an
established production timeout defect.

### Retire the benchmark's real window

Evicting only editor/highlighter caches left the coordinator/window/hosting-view
lifetime, parse sessions and observers active in subsequent tests. The repair
removes the controller from its coordinator and closes its window through the
normal disposal path. It also uses a private preferences suite and a no-write
session store, so the benchmark does not consume or publish the user's session.
Window-frame autosave still follows the existing production defaults path;
broader AppKit preference isolation remains part of the fixture audit.

| Controlled sequence | Whole sequence | Close-recovery case |
| --- | --- | --- |
| Original teardown on `272933c4` | 96.820 s | 59.234 s |
| Fixed teardown | 1.477 s | 0.632 s |
| Remove only window retirement again; retain isolated settings | 102.206 s | 61.942 s |

The new regression fails all four checks with the old teardown: closed state,
external-file disposal, coordinator removal and parse-session eviction. The
negative control distinguishes window retirement from settings isolation.
The final full app-target run on `0b85e6f0` completes the same close-recovery case
in **0.601 s**. This establishes a contributor to the observed suite-order stall;
it does not close every window/WebKit hang criterion or measure user latency.

The benchmark covers 20 cache identities in one controller. Its description now
states this limit; it is not proof of opening/switching 20 native `NSWindow` tabs.
Its 5,000 ms construction and 50 ms cache-hit bounds remain unchanged.

## Validation outcomes and limitations

| Surface | Actual result |
| --- | --- |
| Full package on `95c3d25f` | Exit 0; 240.871 s test execution, with the same two known Neon replacement-edit issues. Existing opt-in skips and the Debug-disabled background experiment remain unchanged. |
| Planned Release performance series on `95c3d25f` | First run passed; second failed at 484.814584 ms against 400 ms in `incrementalKeystroke1MB`. Third run was not executed. This gate is failed. |
| Fresh-directory Release app/CLI and app tests on `95c3d25f` | Built and passed; the close-recovery case took 0.616 s. Fresh compilation exposed two additional nonisolated app-test suites, subsequently fixed. |
| Final unsigned Release app/CLI on `0b85e6f0` | Both passed with `-warnings-as-errors` verified in app-owned compiler commands. No app/CLI Swift source warnings. |
| Final test build and non-UI app-target run on `0b85e6f0` | Passed with warnings-as-errors in the app, unit-test and UI-test compiler commands; no actor-isolation warnings. Test execution took 41.666 s. UI tests were compiled, not executed. |
| Strict SwiftLint, SwiftFormat lint, clean committed-source compliance and final pin check | Passed on `0b85e6f0`. |
| Release compliance on the exact `0b85e6f0` source archive | Failed with the same eight unresolved provenance/product decisions. No artifact compliance approval. |

Applying warnings-as-errors globally first failed because Xcode's existing
package policy also passes `-suppress-warnings`. That diagnostic attempt is
preserved. A validation-only configuration then scoped the extra flag to
app-owned targets; inspected compiler commands confirm the flag is active there
and absent from package targets. No repository setting, package suppression
policy or dependency pin was changed. This is not a warning-free claim for the
entire dependency/tool chain.

The previous warning inventory's “12 UI-test files” was incorrect: six files
contained those warning locations; the others were compilation lines. The fresh
build also found `EditorStatusBarViewTests` and `LineEndingStatusItemTests`, now
corrected in the final code.

## Failed performance gate and remaining diagnostics

`incrementalKeystroke1MB` directly measures the pinned Markdown block parser on
a roughly one-megabyte fixture, bypassing the app's size fallback. The timer
covers reparsing after correctly scaled UTF-16 edit geometry. The grammar reuse
checks passed in the same run and retain evidence of missing Markdown section
reuse. The parser, grammar, benchmark, limit and lock did not change in this work.
These facts identify the measured path; they do not explain this overrun.

One fixed diagnostic invocation then collected three predetermined wall/thread
CPU samples with the same 400 ms assertions: 170.378/169.995, 161.208/161.170 and
163.937/163.844 ms, with nominal thermal state. The slow interval did not
reproduce. Those CPU-bound samples neither explain nor replace the failed
candidate run. Source was restored exactly. No repeated search for a green
performance series occurred. #203 remains open, including its much stricter
fully highlighted product budget.

The subsequent [independent review and fixed context experiment](INDEPENDENT_REVIEW.md)
retain exact `e16be9f7` provenance. Isolated and full-selection parser samples
were 162.661291 and 163.004292 ms, but the full selection failed the unchanged
editing-assist 50 ms ceiling at 56.881709 ms. The declared stop condition ended
the experiment before the remaining two invocations. Neither overrun is explained
by these successful parser samples; the performance gate stays failed.

The fresh test build reproduces 24 dependency-scan warnings. The evaluated
manifest and Xcode's printed graph already contain the named direct/transitive
edges, so stale records alone do not explain them. AppIntents metadata messages
and the fresh-build cmark umbrella-header diagnostic are also retained. No
dependencies or checking modes were altered to silence them.

AppKit table-delegate reentrancy and SwiftUI state-during-update warnings persist
in app tests. A standalone, unshown SwiftUI sidebar/window probe did not reproduce
the warning. A bounded LLDB symbol probe timed out at launch without obtaining a
stack; its identified helper was cleaned up. No user-app attachment, security
setting change or input occurred. The real app update path still needs a
discriminating reproduction or stack capture; no benign-framework explanation
is claimed.

## Review and proposed external change

The inherited checkpoint and full hosted logs have been reviewed, and the new
local corrections have author review and negative controls. **Separate source
review through `e16be9f7` found no concrete regression; the owner's acceptance
remains pending.** The [review](INDEPENDENT_REVIEW.md) also records a pre-existing
timing-boundary coverage gap, unexecuted native UI paths and synthetic WebKit
coverage. It is not performance or release approval. PR #480 is
still draft/open at `60f779fc`, with base `4aa46bfa`; no hosted result covers this
candidate. The original rendered-run mismatch remains unexplained and its
equality assertion remains enabled. Manual Simplified Pinyin proof remains
Debug-only; automated CJK coverage, other input methods, candidate mouse
interaction and long compositions during restore are not established.

The concrete eventual external change is to fast-forward remote
`integration-final` from its verified `60f779fc` head to the reviewed local
`fix/ci-timing-contracts` tip, updating the existing draft PR #480 and triggering
fresh hosted CI. That action is **not yet authorized or performed**. Recheck
both remote refs first; do not overwrite intervening work. The failed performance
gate must remain explicit in any proposal. No merge, release, signing,
notarisation, upstream submission, issue closure or unique-work deletion occurred.
All 22 issues remain in the [acceptance register](../../../OPEN_ISSUE_ACCEPTANCE_REGISTER.md),
including #53 and #203.
