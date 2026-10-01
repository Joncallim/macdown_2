# Downstream implementation-readiness review — 26 September 2026

## Outcome and scope

All 13 downstream issue hand-offs were reviewed again. Nine were revised in place: #17, #18, #53, #113, #115, #116, #117, #118 and #121. Four retain their existing design: #79, #88, #119 and #120, with narrow interpretation clarifications below. Their relevant current-master source delta was inspected rather than treating old descriptions as current implementation.

The initial four review passes covered baseline/compatibility, API semantics, adversarial behavior and dependency/evidence structure. The continuation added two focused passes on prerequisite enforcement and physical resource lifetime. All six are self-review lenses, NOT independent reviewers or a second provider's approval. There are 28 recorded correction groups. No Swift/AppKit/WebKit/Quick Look/VoiceOver, signing or migration execution occurred.

This is complete architecture coverage and a sequenced execution contract, not a claim that every issue can begin broad coding immediately. E22 remains the protected upstream work. Six first-step probes and real identity/artwork/account/QA inputs remain explicit. Pure/value/infrastructure units can begin when their listed prerequisites are met. A failed probe blocks dependent integration for a focused correction; it never permits a weaker hidden fallback.

## Recovery provenance

Original architecture: PR #125, commit `b2c6d19ef453b571f4eb5eb020accfa84305fb60`, source baseline `83a79a4572e23a781b2cf370dd2b407fe7409d09`.

Reviewed restored master: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`. The comparison found 40 later commits concentrated in E22, its tests, package resources and planning. Those changes did not implement all the downstream obligations.

The owner confirmed accidental closure during the repository reset. Reopen attempts through PR and issue endpoints failed with 422; GitHub retained the reverted-fork base in the closed PR metadata despite repaired branch ancestry. Recovery commit `716b48e7a05ded4e74c64a275f3854942dec51e1` preserves original architecture and restored master as parents. Its tree is restored master plus the unchanged original downstream subtree. No force-push was used.

Open replacement PR #147 is the current architecture workspace and is linked from #125. #125 remains the historical record; it was not falsely reported reopened. All original hand-offs/commits remain recoverable. No write to master, active E22 source/plan/workflow, design branches or implementation PR was performed.

## Pass 1 — Baseline, scope and compatibility

Reconciled current source delta and live issue contracts with completed versus in-flight E22. Inspected EditorTextSystem+Selection, DocumentEditorSplitView+EditorPane and EditorSettings; preserve the actual selection model and same-system source/line-index pairing. Old test/catalog counts and the assumption E22 is still at Slice 2a are not current evidence.

MostlyText, mostlytext.app and mostlytext.dev are settled owner inputs. Technical identifiers and approved design deliverables are separate inputs from their own records. The design lane is untouched, and an owner-waived study gate must not be revived or mislabeled passed.

## Pass 2 — API and semantic feasibility

Inspected pinned Textual PatternProcessor and current MathPreviewPreprocessor. Textual's attributed-run processing occurs after Markdown interpretation, so simply replacing its later tokenizer cannot restore already-consumed source escapes. Reviewed FileStore's actual snapshot/text-publication boundary, ExportService sentinel mechanics, resource/static HTML/print paths and primary API documentation.

Public XNU declarations for O_NOFOLLOW_ANY/O_RESOLVE_BENEATH are not installed-SDK/minimum-OS race proof. QLPreviewReply's factory is synchronous, not an async-render callback. Swift async/nonisolated syntax is not automatically proof of off-main execution under all compiler isolation settings. Named probes now resolve these empirical questions before broad integration.

## Pass 3 — Failure, concurrency and regression findings

These are architecture corrections, not claims that production code has already been fixed. A26–A28 were added by the continuation passes below.

| ID | Problem | Corrected contract |
| --- | --- | --- |
| A01 | Required showsStatusBar can reject old editor-settings JSON and trigger whole-domain defaults. | #53 compatible historical decoding before writers/import; preserve present values and unknown raw blobs. |
| A02 | A tokenizer called after Markdown cannot restore consumed escaped dollars. | #116 pre-parse source admission and registered transport into typed attachments; old math pass disabled. |
| A03 | Flattening display-math newlines changes newline-sensitive TeX comments. | #116 preserves original equation bodies/newlines. |
| A04 | Invalid currency candidates can consume a later real equation. | #116 forward candidate-abandon/reconsider rule and mixed-price/math fixtures. |
| A05 | Direct NSTextView selection writes bypass E22's cached plural caret model. | #116/#117 use controller selection/reveal behavior and validate source lifetime/generation. |
| A06 | Untitled/single-file requests were modeled as directory authority. | #121 explicit none/singleFile/directory grants; Quick Look never infers parent permission. |
| A07 | Concurrent reads can each consume the same apparently remaining quota. | #121/#118 reserve before suspension and maintain cumulative delivery accounting; A27 refines release timing. |
| A08 | Immutable load identity does not supply correct response MIME metadata. | #121 explicit Content-Type/charset alongside response CSP and actual resource tests. |
| A09 | Cancelled waiters were confused with drained workers. | #121/#113 retain actual worker occupancy and bounded retired work. |
| A10 | #117 required E23's palette while E23 required #117. | #117 starts with existing value Theme; E23 adapts later without changing snapshot identity. |
| A11 | A global 8 MiB anchor DOM gate would reduce normal export support. | #117 capability-scoped analysis; ordinary no-TOC export retains current limits. |
| A12 | Fatal TOC failure contradicted Quick Look's best-effort isolation. | Preserve that contribution's source/diagnostic and continue the preview; valid TOCs still must navigate. |
| A13 | Replacing resource pathname strings can rewrite literal prose/code. | #118 registered generated URL slots and checked occurrence/context, never broad textual substitution. |
| A14 | Filesystem names were treated as already-safe HTML URL attributes. | Separate component percent encoding from HTML attribute escaping; test quotes/percent/Unicode. |
| A15 | Same-stem .html/.htm or case aliases can contend for one assets namespace. | #118 short opened-parent publication serialization and primary-bound manifest ownership. |
| A16 | Hash-then-unlink races replacement of the live path. | #118 quarantine-first retirement, verify moved object, preserve/restore mismatches without overwriting. |
| A17 | PDF cancellation had no exact publication commit point. | Cancellation before promotion prevents publication; successful committed output is not retroactively cancelled. |
| A18 | New theme IDs on every import break reimport/update idempotence. | #113 stable IDs, explicit Replace/Copy, byte-identical no-op and journaled retries. |
| A19 | A synchronous Quick Look factory could repeatedly start async work. | Selected frozen-payload factory; A28 makes its timing tradeoff explicit rather than an API mandate. |
| A20 | Timeout could still wait behind the uncooperative work it supposedly bounded. | Prebuilt fallback, independently viable reply control, actual worker drain and a discriminating QL-REPLY probe. |
| A21 | Shared decoding could create document/recovery state or infer a manual override. | Stateless bounded FileCore byte decoding, no app-session lookup or lossy heuristics. |
| A22 | CLI --wait can miss a close between open and subscription. | #18 atomic receipt/subscription admission and retained ordered terminal results. |
| A23 | Migration could omit snippets or overwrite choices after old-schema fallback. | #18/#53 authoritative final E22 content inventory and compatible pre-writer decoding. |
| A24 | #115 closure and final E16/signed-artifact preparation were circular prerequisites. | Canonical software-S/private-V/public-P sequence preserves every acceptance obligation. |
| A25 | Static checks, minimum-of-trials benchmarks or self-review could be overstated as broader proof. | Explicit evidence kinds, full measurements/runtime sentinels and honest reviewer provenance. |
| A26 | Acyclicity/probe inventory still accepted missing prerequisite edges and completion inputs. | Checker now enforces probe ancestry/ownership, complete software-S ancestry, protected work and required QA/signing/authorization inputs. |
| A27 | Consumer terminal state could refund capacity while reads or cached payloads were still alive. | #121 independent consumer/worker/payload/delivery lifetimes and reservation transfer, with cancellation-storm tests. |
| A28 | Reply delivery could be mistaken for released memory; precomputation was presented too much like an API rule. | #113 bounded retained reply holders, no closure cycles, and a probe of the selected placement against Apple's factory recommendation. |

## Clarifications for retained hand-offs

**#79:** Eviction removes a timed-out worker from reuse, not from real process/memory accounting. Retain its occupancy until completion/termination is observed; do not create unlimited replacements. DIAGRAM-CONTEXT checks actual bundled option names and all three engines. Neutral defaults do not guarantee arbitrary author-specified colors.

**#119:** Bounded authoritative snapshot/digest admission stays in FileCore and is shared across its monitors/windows. It does not depend on Preview or DocumentPresentation. #121's contained-resource reader has a different contract; do not create a dependency cycle to call these one reader. Revalidate lifetime after moving conflict reads off MainActor, and measure aggregate application load.

**#120:** A logical save token identifies one operation, not a permanent document lifetime. CLI --wait follows a controller-owned lifetime through successive Save As operations and must not reuse one save attempt's token. The save-progress/close wording architecture otherwise stands.

**#88:** Engineering hooks and final-artifact public-UI proof remain separate. Reconcile real post-E22 focus/command behavior rather than retaining stale expectations. Never run untrusted PR code in a privileged interactive/signing environment.

**Export retirement:** The quarantine is a private owner-only, operation-owned staging namespace with unpredictable exclusive names and validated descriptors. It is not a sandbox against arbitrary same-UID code intentionally changing that private namespace. Unknown/mismatched bytes are retained/reported, never deleted by hash-shaped filename. Do not claim filesystem compare-and-swap from a precheck plus rename. Reused binary conditional-publication behavior needs exact tests; an unplanned cross-module publisher requires a focused architecture correction.

## Pass 4 — Dependency and evidence structure

readiness.json contains 13 hand-offs, 48 nodes and six named probes. Nodes represent inputs, upstream work, implementation, probes, verification and release gates—not 48 new issues or a requirement for 48 PRs. Reviewable changes can be combined/split without violating ownership/prerequisites. Tested prerequisite availability is separate from whole-issue closure.

The initial checker caught an incomplete inventory during authoring and passed 13 structural tests afterward. That was useful but incomplete: pass 5 found missing critical dependencies it still accepted. The manifest itself needed no change; the checker was strengthened.

Validated manifest SHA-256: `7a699ce616724e8a87a8ea56bcd38eca111eb507e69625eb0a1855851c69fa23`.
Manifest Git blob: `98f0bcd14f4400f12484f76383c25bb5a1fa2583`.

Run from a checkout:

```sh
python3 planning/downstream/validate_readiness.py planning/downstream/readiness.json --self-test
```

The local container did not contain a full clone. File-presence checks used explicit filenames returned by GitHub, not placeholder files. The checker reports supplied_list versus filesystem. Remote blob identity and PR scope are checked separately. This is not swift test, CI, app execution, migration or a final release-gate validator.

## Pass 5 — Adversarial prerequisite validation

Resumed from live #147 at `fd1752bd37dfd93ca8d1cd1bb6e8105ba7a53eed`. Reconstructed the fetched checker/manifest and verified exact Git blobs `c53a789f52d2b7746fc3b713803b929710de560e` and `98f0bcd14f4400f12484f76383c25bb5a1fa2583` before testing.

The old checker returned no errors for three separate mutants: resource-reader without RESOURCE-OPEN; software-S without any prerequisites; and final-localization without native-reviewers. Its original 13 tests still passed. These were actual local checker tests, not macOS tests.

The correction requires each probe exactly once, under the right owner and upstream of its actual consumer. All implementation/probe work must be upstream of software-S. Baseline, protected work, translation/native-review/signing and final authorization prerequisites remain required. Malformed fields, duplicate dependencies, reclassified gates and per-unit runtime claims are rejected. Negative cases identify units by stable ID and require detection of the intended defect, rather than accepting any unrelated error. Valid row reordering remains valid.

**39 positive/negative checks pass in normal Python and python -O.** Self-tests use explicit conditions, so optimization cannot disable them. Python compilation passed. The manifest remains unchanged at 13 hand-offs/48 nodes/six NOT_RUN probes. These checks validate only planning structure; they cannot authenticate future execution evidence or authorize implementation/publication by themselves.

## Pass 6 — Completion versus physical resource lifetime

Re-read revised math, anchor, export, HTML Preview and Quick Look contracts for remaining interactions. #121's broad terminal-release wording could still refund buffers while stopped reads or completed cached snapshots retained them. It now specifies independent consumer permission, actual worker occupancy, retained-payload ownership and cumulative delivered-byte accounting. Cleanup survives UI cancellation/disposal, with exact-once transfer/release and out-of-order/cancellation-storm tests.

#113 applies that distinction to delivered QLPreviewReply objects. An escaping factory captures only a minimal immutable payload holder and reservation, not its reply/provider/request/renderer. Initial provider-owned global retention caps supplement per-reply caps. Callback completion is not deallocation evidence; framework copies remain separately measured. These are design requirements, not native memory measurements.

Apple's initializer documentation recommends heavy work inside dataCreationBlock. The hand-off now explicitly states that precomputing frozen data is a project choice, not an API requirement. QL-REPLY must test loading/callback/cold-start timing and fallback viability before broad integration. A synchronous factory signature cannot settle that placement tradeoff.

Primary references checked: Apple QLPreviewReply/dataCreationBlock documentation and Swift Task.cancel documentation, with exact URLs retained in the affected hand-offs. Cooperative cancellation does not imply arbitrary running work has stopped or released its memory.

## Six first-step probes — all NOT_RUN

| Probe | Exact prerequisite question | Dependent implementation |
| --- | --- | --- |
| RESOURCE-OPEN | Does the shipping SDK/minimum OS constrain real opens under leaf/intermediate/ancestor/root races, preserving admitted positive cases and bounded reads? | #121 reader and #118 consumption. |
| MATH-ADAPTER | Do real pinned Textual/SwiftUIMath inputs survive source-aware marker transport into accessible typed attachments with correct ranges and no escape/newline corruption? | #116 native integration. |
| ANCHOR-PARSER | Do actual parser and browser/WebKit fixtures agree on authored IDs/entities/context and unique emitted targets without rewriting source or shrinking normal export support? | #117 anchors and shared presentation. |
| PDF-PRINT | Does the real native print callback preserve responsiveness, exact-once completion and truthful cancellation/disposal? | #118 PDF integration. |
| DIAGRAM-CONTEXT | Which verified bundled options produce opaque neutral defaults consistently in native/vector output without weaker security? | #79/E23 rendering and calibration. |
| QL-REPLY | What are the actual permissions, factory/cid/retained-reply lifecycle and viable fallback execution placement, including Apple's recommended factory timing? | #113 broad Quick Look integration. |

Each probe has positive controls, discriminating failures and a decision output in its hand-off. Failure requires a focused revision before dependent work. It does not authorize new renderer ecosystems, broad entitlements, guessed APIs or relaxed acceptance. Source inspection does not substitute for execution.

## Per-issue implementation entry

| Issue | Ready entry when prerequisites are met | Remaining acceptance gates |
| --- | --- | --- |
| #121 | RESOURCE-OPEN and capability/reader tests. | Probe, actual WebKit/network/MIME, physical resource lifetimes and Release UI. |
| #117 | Pure destinations/index and ExportOrigin snapshot. | ANCHOR-PARSER, actual links/navigation, parse measurements and E22 registry result. |
| #116 | MathSyntax/exclusion tests and pinned dependency preparation. | MATH-ADAPTER, native accessibility/VoiceOver, parity/performance/export proof. |
| #118 | Registered assembly/publication after reader/snapshot prerequisites. | PDF-PRINT, resource/publication races, recovery/size/memory and real UI/PDF. |
| #79 | Structured neutral context after palette values. | DIAGRAM-CONTEXT and all-engine print/limits/lifecycle measurements. |
| #113 | Palette/catalog/decoder after E22; minimal QL-REPLY independently. | Shared prerequisites, reply lifetime/cold timing, Finder/security/performance/artwork/identity. |
| #120 | Logical-save registry and explicit-origin panel tests. | Real save/close/Open UI and latency evidence. |
| #119 | Bounded FileCore admission/lifetime work. | Full external-file UI matrix and Release measurements. |
| #88 | Isolated harness/test-plan and fixture/assertion repairs. | Suitable interactive Mac and final exact-artifact critical suite. |
| #53 | SETTINGS-COMPAT decoding, then frozen-schema import map. | Final settings/theme inputs, consent/retry/live migration and E22 parser half. |
| #18 | Bootstrap/CLI/updater after storage/identity prerequisites. | Authorized credentials, stateful signed update/Gatekeeper and P authorization. |
| #17 | Inventory/test preparation; final pass after S. | Translation access/native QA/plurals/layout/non-English app proof. |
| #115 | Finite evidence manifest and validation preparation. | S, final E16, all exact-artifact V obligations and separate P authorization. |

No issue is closed by this review. No public release or production merge is requested automatically. Claude should finish E22, adopt this architecture through the normal PR process, rebind exact interfaces once, and execute dependency-ready units with the named probes first. There is no blanket bug-free claim and no permission to mark blocked runtime evidence passed.
