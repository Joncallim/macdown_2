# Attribute the restored highlighting mismatch in its test process

The synthetic editor can restore full highlighting after shrinking yet retain
styles that differ from a fresh reference. The latest retained failure is
[run 39248566829](https://github.com/Joncallim/macdown_2/actions/runs/39248566829)
at diagnostic head `531a99fc27d3510eaeba5ff930fac146c0f29677`. Waiting and ordinary
invalidation did not repair that fixture; rebuilding the highlighter did. This
experiment asks whether incorrect styles originate in query output, a later
application, or TextKit attribute application. It does not select a product fix.

The fixture uses a 6,000 UTF-16 cutoff, 4,500 restore threshold and 200 ms idle
delay. A mounted native reproduction at production settings remains unverified.
The production 8,192 cutoff, two-second idle delay and all dependency pins stay
unchanged. The inherited zero-sleep-tolerance experiment remains diagnostic-only;
its passing cleanup assertions did not establish the cause of earlier overruns.

## One execution, with preserved source identity

Continue on existing draft PR #496 and its existing worktree. The diagnostic
package step exports the actual committed `MacDown2/Packages` tree into an isolated
temporary directory, applies the reviewed package and Neon patches, then runs
`swift test --no-parallel --force-resolved-versions` once. There is no preceding
uninstrumented test suite or separate trace VM. Both emitted fixture traces must
identify the actual Swift Testing helper observed in this same invocation.

The original package tree must equal `e690fa0cf0655c2a26889b53ca467feda05ee82c`,
from preserved head 531a99fc. It differs from production package tree
`54fa64b226ee4cfbf35ee3edc9fce09c12e58b75` only by the earlier test-fixture sleep
tolerance experiment. Production candidate
`ad79f2773f2cbaf8bb78bdb796b1d11b411be79b` remains untouched.

The collector records actual checkout/merge/head/base/tree, the exported source
archive hash, patch and preimage hashes, all patched-file hashes before/after,
all 22 locked dependency revisions before/after and the unchanged lock hash
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
Only the isolated Neon checkout at pinned revision
`484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165` receives the diagnostic Swift patch.
Its manifest and deployment target are not changed. The original checkout must
remain clean. Root-source attestation and intentionally patched-copy attestation
are distinct checks.

The corrected crash observer runs the test command directly, retaining its
original exit independently of trace/provenance gates, exact helper birth/parent
identity and executable/test-image seals. It adds no test timeout, process-group
change, signal, debugger, retry or product-side sleep. Only the explicit trace
output environment and regular test log file are supplied to this invocation.
Setup/build commands retain bounded owned-process handling. The complete test
log, trace JSON, crash evidence and provenance are uploaded even after failure.

## Observations and unchanged behavior

Reuse and extend the bounded synthetic-only recorder from PR #494. Each query is
linked to its immutable client, parser tree and client-binding generation. Record:

- Ordered named ranges and token applications, including duplicate/overlapping
  tokens, action, optional clear range, admitted/current versions and content hash.
- Application begin/end, existing TextKit 2 rendering attributes before/after,
  and actual setter arguments: attributes from the original provider invocation,
  requested/clamped range, and whether range conversion rejected the write or
  `setRenderingAttributes` returned. No provider is called a second time.
- The existing styler invalidation/validation target, version and returned action.
  No subsequent query is not by itself evidence of a parser failure.
- Explicit begin/returned markers around the existing invalidation and both
  language-change calls, plus each original failure probe's rendered-run hashes.
  The original primary reference value has a stable hash; later reads are labeled
  as after the primary assertion.

The original edits, pauses, clocks, assertions, comparison evaluation order and
failure-first probes remain. No holds, omissions, extra invalidation, cancellation,
manual clock, task joins, drains, layout forcing or second styling call are added.
The macOS 26 test target supplies a read-only TextKit 2 signature callback, removed
at session finish; the dependency's original deployment target stays intact.

Only the two synthetic restore cases and their registered fresh references are
recorded. No raw document text or environment dump is exported. Each case retains
the existing 32,768-event/16-MiB bound, dropped-event reporting and unfinished-work
list. File output occurs after its test/probes end. End of collection, return from
an invalidation call, and an empty observed-work list do not establish quiescence.
An early process crash may leave no trace. Existing rendering attributes are not
a pixel-paint or mounted native acceptance oracle.

## Fixed validation and decision boundary

Before hosted execution: independent source review; static checks and existing
crash-observer controls; integrity-validator corruption controls; one local
filtered execution of the two original restore cases to validate compilation and
recording. Retain any failure before repair. The local execution validates the
diagnostic, not the historical hosted cause. Then run one full hosted suite on
the reviewed exact head, with heavy work serial. Do not rerun unchanged for green.

A failed primary comparison with complete same-process evidence can distinguish
incomplete provider output, later overwrite/rejection, or divergence during/after
attribute application. Interpret exact names, ranges, versions and signatures;
token count alone is insufficient. A passing instrumented case is inconclusive
about the historical mismatch because recording changes scheduling. Retain all
prior failed runs and the separate passing trace from PR #494.

Any production correction requires a causal finding, fail-before/pass-after
regression, independent review and full actual combined-candidate validation,
including required Release performance suites. No general newest-query filter,
rebuild-on-edit workaround or dependency update follows from this diagnostic.
Native, preview ownership/draining, warning, strict-compliance, private-scanner,
CJK-coverage and owner gates remain. PR #480 remains draft/unmerged, issues
#53/#203 remain open, and no master merge, signing, notarization, release, upstream
submission or deletion of unique work is included.
