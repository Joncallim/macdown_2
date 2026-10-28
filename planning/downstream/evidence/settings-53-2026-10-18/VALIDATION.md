# Settings compatibility checkpoint validation

## Owner outcome

An explicitly null status-bar setting now follows the existing unreadable-data
path instead of being silently accepted as true. A genuinely absent field still
defaults to true, preserving older valid editor preferences. The legacy
declaration map exposes remaining conversions and policy decisions without
installing an importer. The isolated write probe establishes concrete gaps that
keep #53 open: future primary replacement, loss of later unreadable generations,
and unreported/unpreserved non-Data values.

Validation used the clean combined candidate
**`5659816625c71503825aac33467f2d1cce3fd03c`**, on CORTANA, 2026-10-18 UTC.
The following commit records evidence only. Its tested source identities are
preserved in [validation.json](validation.json); execution results retain their
actual candidate provenance. No Jonathan preference values were read or changed.

## Checks and scope

| Check on `56598166` | Outcome |
| --- | --- |
| Debug and Release AppSettingsTests with locked packages | Passed, including absent, explicit Boolean and malformed status-bar fixtures. These were filtered settings runs, not full package or performance runs. |
| Legacy declaration checker and its negative controls | Passed. Covers 52 stored, four calculated and two transient declarations. Does not prove aliases, import conversions or precedence. |
| Strict SwiftLint and SwiftFormat lint | Passed. |
| Source compliance from clean committed archive | Passed. |
| Release compliance from that archive | **Failed with eight findings.** Expected exit 1 is retained as a release failure, not approval. |
| Unsigned Release app and CLI | Passed after correcting the validation-only compiler policy described below. Actual app/CLI compiler commands contain optimization and warnings-as-errors. |
| Dependency and source checks | All 22 SwiftPM and 22 Xcode checkouts were clean and matched the unchanged production lock. Generated Xcode lock matches; committed diff whitespace check passed. |

Heavy commands ran serially. The environment was Apple M3 Pro, macOS 26.5.1
(25F80), Xcode 26.6 (17F113), Swift 6.3.3. The generated project came from
XcodeGen, with no hand edits. Fresh DerivedData for this candidate is retained,
including hashes of the unsigned app and CLI executables. Neither was launched.
App test targets and native UI were not executed in this settings slice.

## Preserved diagnostic failures and warnings

The initial app command accidentally reapplied a global warnings-as-errors
setting that had already been diagnosed in the earlier integration validation.
Package targets also received Xcode's existing `-suppress-warnings`, so the
compiler rejected the conflicting flags and the build exited 65. The sequence
stopped. Its original log and command record remain intact.

A single corrected continuation used a byte-identical copy of the previously
established validation-only configuration, adding warnings-as-errors to the app
and CLI targets. No repository source, package policy or pin changed. Inspected
compiler commands confirm the requested flag and Release optimization. The
fresh app log retains the AppIntents metadata-extraction warning; no app/CLI
Swift source warning was reported. This is not a claim that the entire package
or tool chain is warning-free.

The Release package compilation also reported the existing redundant `#require`
at HighlightingSizeFallbackLifecycleTests.swift:101. Independent review verified
that the file is byte-identical to the pre-slice baseline, the line originated
in `ff59cc6d9cd0635d5bc94a650e961f5a8187f2bc`, and a previous diagnostic log
already contains the warning. It remains an outstanding highlighting-test
warning outside this bounded settings change; it was not suppressed or fixed.

The earlier outer-sandbox manifest failure and the real baseline null-regression
failure also remain in the [evidence manifest](evidence-manifest.json). Hardware
metadata was initially denied by the shell sandbox; a permitted read captured
it alongside process ownership. No automatic approval review denied an action.

## Review, ownership and remaining gates

The [independent reviewer](INDEPENDENT_REVIEW.md) found no material source or
claim defect in the bounded correction and confirmed the completed validation
bindings and final evidence. Independent review did not execute tests and does not replace owner
acceptance. This task inspected the integration worktree and running jobs;
the preserved Claude sessions had working directories outside this checkout and
were not interrupted. Final clean-head ownership is recorded separately in the
raw evidence directory after the evidence commit.

The write-protection behavior needs explicit shared-writer/admission/recovery
architecture reconciliation before implementation. #53 still requires complete
conversion semantics, precedence, consent, idempotence/restart evidence, final
E23 destinations and the isolated-account E17 migration path. The declaration
checker is not yet a hosted CI requirement. There is no new live-apply or native
UI proof.

The parser result **484.814584 ms / 400 ms** and editing-assist result
**56.881709 ms / 50 ms** remain failed and unexplained. No performance suite was
rerun. The original hosted timing/rendered-run issues, limited manual Pinyin
evidence and unproved automated CJK coverage remain explicit in the prior
[integration evidence](../ci-timing-2026-10-18/FOLLOWUP.md). The 8,192 UTF-16
fallback and experimental dependency isolation are unchanged. #53 and #203
remain open; no hosted result covers this candidate.

Eight release-preflight failures remain, including the outstanding attribution
and source-publication work. Its stale font-decision row still needs inventory
reconciliation with the recorded KEEP decision; this slice does not reopen it.
Nothing was pushed, merged, deployed, signed, notarised, submitted upstream or
changed in an external issue. No unique work was deleted.

The next safe independent intake is #121: reconcile the current preview handler
with the cancellation/stale-request contract and reproduce one deterministic
request-lifetime mismatch before proposing changes. This is a recommendation,
not implementation or native WebKit proof. Owner review and authorization for
external changes remain pending.

Raw evidence is retained at
`/Users/jonathanlim/GitHub/_cleanup-archive/settings-53-d3cc8883-2026-10-18/`.
