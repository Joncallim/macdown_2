# Combined overnight validation on 400d475c

## Owner outcome

The combined local corrections pass the selected non-performance package and
app-target gates in one serial run. Debug and Release app/CLI builds and ordinary
unsigned artifact compliance also pass. This is a consolidation checkpoint, not
release acceptance: known correctness issues, runtime/build diagnostics, earlier
performance and hosted failures, seven compliance release findings, native paths
and owner acceptance remain open. See the [short owner checkpoint](../../OVERNIGHT_CHECKPOINT_2026-10-18.md).

No product source changed during this validation. Its exact candidate is
`400d475caaae130cdce1f6de4c6904027e700827`, tree
`28f78670ce5ff43e06c3e7cf36aaacb2f9d8e763`. The source archive SHA-256 is
`5f892f970b888af53f69aff8cb2aa6fc8b6530d2a94e1b4f3626a30a0d0b0cc2`.
The complete overnight source review covers handed-off
`60f779fc0f7324cd5dd3b7b503030e9c22d7d44f` through that candidate. Later
documentation commits do not relabel these builds as tests of another head.
[source-equivalence.json](source-equivalence.json) records every unchanged
top-level Git object outside the documentation tree and the three permitted
checkpoint paths. The final commit identity, clean status and complete diff-path
verification are sealed separately in the raw `final-checkpoint/provenance.json`.

## Ownership and environment

The integration worktree was clean on `fix/ci-timing-contracts`. Before validation,
process inspection found no active Claude job rooted in this worktree and no
competing heavy validation. Two sleeping Claude sessions were rooted in the
GitHub parent directory and a separate archived slice7a checkout; neither was
interrupted. The handoff was read from the preserved dependency worktree.
[ownership.json](ownership.json) records the initial snapshot.

CORTANA ran macOS 26.5.1 (25F80), Xcode 26.6 (17F113) and Apple Swift 6.3.3.
All timestamps in the command record are UTC; Xcode runtime log timestamps use
the machine's +08:00 timezone. Commands ran serially, with fresh Xcode DerivedData
for this pass and the existing package build cache. No gate was retried. The app
test invocation ran from 21:13:18 to 21:14:37 UTC on 18 October 2026.

Raw evidence, source archive, complete logs, generated project, test result bundle
and Release app are preserved at:

`/Users/jonathanlim/GitHub/_cleanup-archive/overnight-consolidation-400d475c-2026-10-18/`

[validation.json](validation.json) records every gate's exact argument array,
working directory, duration, result, log digest, load and clean-head check. The
two runner scripts preserve the original command selection; they are historical
evidence, not an instruction to rerun. [evidence-manifest.json](evidence-manifest.json)
identifies raw files by length and SHA-256.
The complete `xcresult-file-manifest.json` remains with the raw result bundle;
its digest is in that inventory, avoiding thousands of result-storage entries in
the repository's readable checkpoint.

## Gate outcomes and coverage

| Gate | Observed result and limit |
| --- | --- |
| SwiftFormat and strict SwiftLint | Pass |
| Package build with locked versions | Pass |
| Package non-performance tests, serial | Pass with two existing Neon known issues; no unexpected failure |
| Debug app and CLI; Release app and CLI | All pass; unsigned, first-party Swift warnings treated as errors |
| App/UI build-for-testing | Pass; this does not execute native UI tests |
| App-target non-performance execution | Pass; 413 cases passed and two existing PDF cases skipped |
| Legacy declaration-map check and its tests | Pass |
| Compliance regressions and clean archived source check | Pass |
| Ordinary compliance on this actual Release app | Pass |
| Source and artifact release checks | Both fail with the same seven findings; exit 1 retained |
| Package lock and both checkout pools | Unchanged; all 44 checkouts match their 22 production pins and are clean |

The package command excludes `Performance|Benchmark` and the separately named
`worstCaseScanStaysWithinAPerKeystrokeBudget` and
`aHundredSecondaryCaretsStayWithinAReasonableDrawBudget` tests. The
[selection summary](package-selection-summary.json) preserves every excluded
identifier and the important retained functional cases; the full identifier list
is hashed in the raw evidence. The existing opt-in
`InlineResolutionReconciliationTests` suite is outside that regex, but its enabling
environment variable was absent and the actual log confirms it was skipped.
Node-count-only Markdown tree-reuse checks, idle restoration, the original
whole-call cleanup deadline, null/missing settings compatibility and functional
boundedness tests remained selected. No performance acceptance is inferred.

The package log reports 2,547 tests with two known issues in
`NeonReplacementEditTests`: typing then deleting a block, and replacing a selection
containing inline ranges. Their existing expected-failure annotations remain;
this pass does not resolve them.

Before execution, Xcode enumerated 415 enabled app cases and disabled only the
two tab-scale benchmarks. [The actual result comparison](app-execution-selection.json)
contains exactly those 415 enabled case identifiers, with no missing or additional
case. The benchmark methods are absent from the executed result. The two skipped
cases instead belong to `PDFExportAdapterTests`: long-document multi-page output
and atomic replacement. Both retain their existing `.disabled` annotations for
the real interactive print/WebKit session requirement. No PDF acceptance follows.
The functional window/background-work teardown passed, as did navigation identity
and scheme-delivery tests. The [Xcode result summary](app-xcresult-summary.json)
also reports dynamic-parameter executions separately; case and invocation totals
must not be treated as interchangeable.

## Warnings and native limits

[Build warnings](build-warnings.json) and [runtime diagnostics](runtime-diagnostics.json)
remain recorded. Xcode reports matching host destinations, skipped AppIntents
metadata extraction, cmark's missing umbrella header and 24 dependency-scan
warnings. The existing [investigation](../ci-timing-2026-10-18/FOLLOWUP.md)
already found declared dependency edges, so a stale-cache explanation is not
established. No dependencies or checking modes were changed to silence warnings.

The app run again reports AppKit table-delegate reentrancy and SwiftUI state
changes during view updates. It also reports excessive live NSWindow counts of
101 and 102. This does not establish a new leak, and the passing teardown test
only proves retirement of its own fixture, not every window in the full suite.
[Earlier retained runs](window-warning-history.json) already reported excessive
window counts before the settings, preview and licence slices, including 101/102
on clean `0b85e6f0`. Different test populations do not establish a trend or cause.
WebKit/Launch Services and intents-service connection
diagnostics are also retained. A passing test result is not evidence these are
benign or that the full native app environment is working. Native UI tests were
compiled only; manual Simplified Pinyin evidence remains historical and Debug-only.
Automated XCUITest did not establish CJK coverage.

## Actual artifact and dependency provenance

[artifact-files.json](artifact-files.json) records all 167 regular files in the
new Release app. [resource-comparison.json](resource-comparison.json) verifies the
exact main-app `Contents/Resources/LICENSE` and `THIRD_PARTY_NOTICES.md` bytes,
Textual's Prism bytes and all 12 font digests against the prior audited artifact.
All 15 resources match. The original three-failure artifact record remains
unchanged; this is a different, corrected build.

The current artifact is thin arm64. No universal-binary claim follows from this
host-destination build. No distribution-signing operation ran: inspection finds
only the linker's ad hoc signature, no team identifier and no sealed resources.
The previous resource-only Release evidence has its own architecture and exact
head; it is not relabelled here. [checkout-provenance.json](checkout-provenance.json)
records both unchanged production checkout pools; experiments remain isolated.

The seven retained release findings are D2 anonymous source availability and
Go/embedded-WASM provenance; Mermaid nested attribution; Tomorrow Light's
name/source decision; Graphviz anonymous source availability, exact source/build
hashes, and linked-library attribution. The complete outputs are retained under
`logs/`. Ordinary compliance is not release compliance.

## Independent interaction review and remaining gates

[The independent validation review](independent-validation-review.md) checked the
complete command-log/source hashes, executed case identifiers, artifact hashes and
locked checkout state. It found no material provenance or selection defect and
identified the excessive-window warning as a reporting qualification.

[Source review](independent-source-review.md) found no new material defect across
preview callback ownership, revoked scheme delivery, settings null validation,
isolated defaults, original cleanup timing, normal benchmark-window retirement
and licence packaging. It distinguishes complete Prism byte attribution from the
partial Mermaid audit. The release-tool fixture's fake policy command is unit-test
isolation, not real distribution acceptance.

A separate [close-callback ownership review](independent-close-ownership-review.md)
found no established lifetime regression from removing unused coordinator
bindings: the app owns the coordinator throughout these callbacks, and eventual
close validates the retired document. A weak non-nil check alone would not prove
lifetime across an await; this is a source assessment, not new native coverage.

Synthetic WebKit callbacks plus a Markdown-window teardown do not prove closing
a native HTML window during active resource work. Delayed root-A work can still
read root B (#121); permission workflow and shipping OS-access decisions precede
immutable contexts, contained I/O and drain/quota implementation. #53's future-data
write protection and migration criteria remain unmet. The 484.814584/400 ms parser
and 56.881709/50 ms editing-assist failures and hosted 160.18/150 and 176.19/150 ms
cleanup overruns remain unexplained. No performance suite was rerun in this pass.
The 8,192 UTF-16 fallback and production dependency pins are unchanged.

The licence screen, native critical journeys, final identity/localisation,
signed-artifact proof and owner acceptance remain open. All changes are local;
PR #480 remains draft and unmerged. No push, merge, signing, publication, issue
closure, upstream submission or unique-work deletion was performed.
