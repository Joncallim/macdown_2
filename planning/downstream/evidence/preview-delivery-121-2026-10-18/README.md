# Stopped HTML resource delivery checkpoint

HTML resource tasks now stop receiving callbacks when stopped, superseded or
disposed during delivery. Each admitted attempt has its own task/view identity
and operation token. Stop revokes first; response/data callbacks recheck liveness;
finish and failure consume ownership before calling out. This removes the
reproduced delivery-after-stop behavior without changing resource permissions.

Validated source candidate: **7efb510c59ac75905a3c3b8fa1472d114ed81f2a**, following
clean baseline `6770251faa9fef1bd679bcd02854add59bb06717`. Source correction
`6d29b55f` is followed by a lint correction in `7efb510c`. Later evidence-only
commits do not change the tested product tree. See [validation.json](validation.json)
and the [implementation boundary](../../issue-121-delivery-implementation.md).

## Evidence that distinguishes the correction

The actual baseline handler was compiled into an isolated diagnostic with
recording WKURLSchemeTask implementations. A response callback calling stop still
received data and finish; stopping from data still received finish. Request
replacement, actual coordinator disposal, nested reuse and an error following
stop also produced disallowed callbacks. Both baseline runs and their copied
source remain retained. These are explicitly ordered reentrancy controls, not
claims about native WebKit callback scheduling.

The corrected controls pass on the committed candidate, alongside the previous
navigation/recovery regressions. Wrong-view and unrelated-task stops leave the
live attempt intact; duplicate active starts are ignored; success/error retire
admission before a terminal callback can reenter. The real coordinator's simple
main-document render control also passes through WebKit and the actual handler.
This establishes a local rendered marker, not hostile-content/network proof.

A separate exact-candidate observation deliberately preserves the unresolved
resource-root defect: delayed A still returns `root-B-sentinel` after replacement
with B. The same diagnostic now reports only `response` after response-time stop.
The former observation is a known failure, even though the observation process
itself exits successfully. It must not be counted as a containment pass.

## Exact-candidate validation

CORTANA, macOS 26.5.1 (25F80), Xcode 26.6 (17F113), Swift 6.3.3. Heavy commands ran
serially. Every command records its clean invocation head, arguments, exit status,
timestamps and log hash. No product AppDelegate, user document or product
preference store was used by the isolated tests.

| Check | Result and limit |
| --- | --- |
| Strict lint and format | Pass on 7efb510c. The prior candidate's lint failure is retained. |
| Affected package preview checks | Debug and optimized Release pass with the committed dependency lock. |
| Source compliance | Pass from the committed source archive. |
| Release compliance | **Fail: eight existing findings remain.** Expected diagnostic exit 1 is not a release pass. |
| Unsigned Release app and CLI | Pass with locked dependencies and first-party Swift warnings-as-errors. |
| Release app/unit/UI test-target compilation | Pass in separate fresh TestDerivedData, optimization and testability enabled, coverage disabled. This is not UI-test execution. |
| Isolated app preview checks | Pass using exact candidate source and freshly built Release package objects, individually hashed. Only the app test import is removed to compile source/tests in one diagnostic module. |
| Real WebKit main-document control | Pass for the simple rendered marker; no hostile corpus or native race coverage claimed. |
| Dependency provenance | All 22 package and 22 Xcode checkouts match production revisions and are clean. Package sources, production pins and 8,192 UTF-16 fallback are unchanged. |

The isolated compiler explicitly links the profiling runtime and writes its output
only to the evidence directory. This is correctness evidence, not performance
measurement. App/CLI artifacts and test-build artifacts come from distinct build
directories. Their hashes and actual optimization/warnings flags are recorded in
[build-inspection.json](build-inspection.json). Toolchain diagnostics remain in the
logs; successful invocations do not claim an entirely warning-free toolchain.
AppIntents metadata extraction, cmark module-map generation and dependency-scan
diagnostics remain recorded build/release gates. Some named dependencies are
already declared; that does not establish a cause or dismiss the diagnostics.

## Retained failure and review

The first committed candidate stopped at strict lint: the delivery helper exceeded
five parameters and a fixture used a non-failable Data-to-String conversion. The
correction prepares the same response headers from the captured request before
delivery, and requires valid UTF-8 in the fixture. No threshold, assertion or
dependency was weakened. The original failure and all baseline failures remain in
the [manifest](evidence-manifest.json).

A separate read-only reviewer found no material issue in the delivery correction
or the lint delta. Its source and evidence review, and exact-candidate disposition,
are recorded in [INDEPENDENT_REVIEW.md](INDEPENDENT_REVIEW.md). This is independent
agent review, not another provider's approval or owner acceptance.

## Concrete blocker and remaining gates

Immutable per-load resource ownership is **blocked at the app's grant boundary**.
HTMLPreviewView receives only FileDocument and infers its parent. The existing
folder API exposes a URL but no transferable preview grant or retained scope owner;
DirectoryLease cannot derive a document-directory lease from an existing directory
descriptor. A pathname check followed by an absolute child reopen would preserve a
race. This is an architecture prerequisite, not an automatic approval denial.
The registry-only work is complete; root integration was not attempted.

Next, reconcile the explicit folder-grant owner, its propagation/revocation and a
contained document-base mapping, then continue fresh immutable WebKit contexts
using the existing reader. Do not infer directory permission from a file grant,
broaden resource roots, or silently remove existing resource behavior. Retain main
source rendering for ungranted documents under the accepted handoff.

#121 stays open: immutable context/root/load identity, Save As/lifetime controls,
contained-reader integration, off-main I/O, worker/payload accounting, aggregate
quotas, real scope balancing, native hostile-content/network tests and minimum
macOS 26.0 evidence remain. This slice does not fix blocking reads or filesystem
replacement races.

#53 shared-writer protection gaps remain. #203 remains open: parser
**484.814584 ms / 400 ms** and editing-assist **56.881709 ms / 50 ms** are still
failed and unexplained. No performance suite was rerun without a causal hypothesis.
Original hosted timing/styled-run failures remain unresolved; manual Simplified
Pinyin evidence is limited to its recorded Debug path and does not prove automated
CJK coverage. Release compliance, owner review and other release holds remain.
No hosted result covers this local candidate.

Master, dependency-trial work and existing worktrees are preserved. No push,
merge, release, signing, notarisation, upstream submission, external issue update,
automation or deletion of unique work occurred.

Raw evidence:
`/Users/jonathanlim/GitHub/_cleanup-archive/preview-resource-121-6770251f-2026-10-18/`.
The final provenance record binds the later evidence-only checkpoint to this
validated product tree and confirms ownership and clean worktrees.
