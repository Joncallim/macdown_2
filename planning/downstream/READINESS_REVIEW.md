# Downstream implementation-readiness review — 26 September 2026

## Outcome and scope

All 13 downstream issue hand-offs were reviewed again. Nine were revised in place: #17, #18, #53, #113, #115, #116, #117, #118 and #121. Four retain their existing design: #79, #88, #119 and #120, with the narrow interpretation clarifications below for #79/#119. Their unchanged relevant code paths were checked through the current-master delta, not assumed to be a new implementation.

This is complete architecture coverage and a sequenced execution contract, NOT a claim that all runtime assumptions are proven or every issue can start broad implementation immediately. E22 is still the protected upstream implementation. Six named first-step probes and real identity/artwork/account/QA inputs remain explicit. Pure/value/infrastructure units can begin when their actual listed prerequisites are met. A failed probe blocks its dependent integration and requires a focused correction; it never permits a weaker hidden fallback.

The four passes were performed within this architecture session. They are distinct review lenses, not independent reviewers or a second provider's approval. No Swift/AppKit/WebKit/Quick Look/VoiceOver/signing execution occurred.

## Recovery provenance

Original architecture: PR #125, commit `b2c6d19ef453b571f4eb5eb020accfa84305fb60`, source baseline `83a79a4572e23a781b2cf370dd2b407fe7409d09`.

Current reviewed master: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`. The source comparison showed 40 later commits concentrated in E22, its tests, package resource declaration and planning updates. The old downstream modules did not all magically become implemented during that interval.

The owner confirmed #125 was closed accidentally during a repository reset. Reopen attempts through PR and issue endpoints failed with 422. GitHub's closed-PR metadata retained the reverted-fork base even after branch ancestry was repaired. Recovery commit `716b48e7a05ded4e74c64a275f3854942dec51e1` preserves both original architecture and restored master ancestry; its tree is exactly current master plus the original downstream subtree. The update was a fast-forward, not a force-push.

Replacement PR #147 is the current architecture workspace, linked from #125. #125 is retained as the historical record, not falsely reported reopened. No write to master, active E22 code/plan/workflow, design branches or implementation PR was performed. All original hand-offs remain recoverable from Git history.

## Pass 1 — Baseline, scope and compatibility

Reconciled current source delta, existing issue contracts and completed versus in-flight E22 interfaces. Explicitly inspected current EditorTextSystem+Selection, DocumentEditorSplitView+EditorPane and EditorSettings; retained actual current selection ownership and same-system source/line-index pairing. Old hardcoded test/catalog counts and assumptions that E22 is still at Slice 2a are not current readiness evidence.

Settled brand inputs are MostlyText, mostlytext.app and mostlytext.dev. Final technical identifiers and approved design deliverables remain separate inputs from their actual owning records. The design lane is not edited here, and a superseded human-study gate must not be revived or mislabeled passed.

## Pass 2 — API and semantic feasibility

Inspected the pinned Textual PatternProcessor and current MathPreviewPreprocessor; the former tokenizes attributed runs only after Markdown interpretation, disproving the earlier tokenizer-only escape fix. Reviewed actual FileStore text-write/snapshot boundary, existing ExportService sentinel mechanics, static HTML/resource/print paths and primary API documentation where needed.

Apple's inspected public XNU header exposes O_NOFOLLOW_ANY/O_RESOLVE_BENEATH. That is NOT proof of the installed shipping SDK or minimum-OS race semantics. QLPreviewReply's data factory is synchronous; it is not an async renderer entry. Swift async/nonisolated scheduling depends on compiler isolation settings and is not automatic proof of off-main execution. These distinctions are now reflected in named probes and explicit executor ownership.

## Pass 3 — Failure, concurrency and regression review

The following corrections are recorded in the revised hand-offs; they are architecture corrections, not claims that the production bugs were fixed in code.

| ID | Problem found in the earlier design or current integration boundary | Corrected contract |
| --- | --- | --- |
| A01 | New required showsStatusBar can reject older settings JSON and cause whole-domain default fallback. | #53 compatible historical decoding before any writer/import; preserve present values and unknown raw blobs. |
| A02 | A shared tokenizer invoked after Markdown cannot restore escaped dollars already consumed by parsing. | #116 pre-parse source admission and registered opaque transport into typed native attachments; old math pass disabled. |
| A03 | Collapsing display-math newlines changes newline-sensitive TeX comments. | #116 preserves original expression body/newlines. |
| A04 | Currency delimiters can consume a later real equation while searching for a valid closer. | #116 explicit forward candidate-abandon/reconsider rule and mixed-price/math fixture. |
| A05 | Direct NSTextView selection writes bypass E22's cached full caret model. | #116/#117 use completed controller selection/reveal behavior; stale equation/anchor identities reject. |
| A06 | A single-file or untitled request was modeled as if every consumer had a directory root. | #121 explicit none/singleFile/directory grants, reused by Quick Look without inferred parent authority. |
| A07 | Several concurrent reads can each see the same remaining aggregate budget. | #121/#118 reserve byte/queue capacity before suspension, with exact terminal release and cumulative delivery accounting. |
| A08 | Immutable load ownership does not by itself supply correct MIME metadata. | #121 explicit Content-Type/charset policy alongside response CSP; real HTML/CSS/font/media tests. |
| A09 | Cancelling a waiter was confused with stopping a blocking read or releasing its worker. | #121/#113 actual-drain slot ownership and bounded retired work; byte caps are not decoded-memory guarantees. |
| A10 | #117 snapshot required E23's palette while E23 required #117. | #117 starts with existing value Theme; E23 adapts later. Unit dependencies are acyclic. |
| A11 | An unconditional 8 MiB anchor DOM check would shrink normal export support. | #117 capability-scoped bounded analysis; no-TOC ordinary export retains existing limits. |
| A12 | Fatal TOC failure contradicted Quick Look's best-effort contribution isolation. | #117/#113 preserve the failed contribution's source and continue preview; valid admitted TOCs still must navigate. |
| A13 | Replacing resource pathname strings could modify literal authored prose/code. | #118 registered generated URL slots, absent marker namespace, exact occurrence/context validation. |
| A14 | Filesystem names were treated as already-safe HTML URL attributes. | #118 separate path-component percent encoding and HTML attribute escaping with adversarial filenames. |
| A15 | Same-stem .html/.htm or case aliases could contend for one companion namespace. | #118 short per-opened-parent publication serialization and primary-bound ownership manifest. |
| A16 | Hash-then-unlink still races replacement of the live candidate path. | #118 quarantine-first retirement, verify moved object, preserve/restore mismatch without overwriting. |
| A17 | PDF cancellation lacked a precise publication commit point. | #118 cancellation before promotion prevents publication; successful committed output is not retroactively called cancelled. |
| A18 | Always generating a fresh imported theme ID breaks idempotence/update semantics. | #113 stable IDs, explicit Replace/Copy, byte-identical no-op and journaled retry IDs. |
| A19 | Quick Look's synchronous reply factory could be used to start async work repeatedly. | #113 prepares bytes/attachments first; repeat factory invocation returns identical frozen data. |
| A20 | An async timeout could still wait behind the uncooperative renderer it was meant to bound. | #113 prebuilt fallback and independently viable reply control, verified by QL-REPLY; timed-out worker remains accounted for. |
| A21 | Sharing app decoding could accidentally construct document/recovery state or infer a manual override. | #113 stateless bounded FileCore byte decoder; no app-session lookup or heuristic/lossy fallback. |
| A22 | CLI --wait could miss a close between open and subscription. | #18 atomic receipt/subscription admission and ordered retained terminal results. |
| A23 | Migration could omit durable snippets or let old schema fallback overwrite user choices. | #18/#53 authoritative state inventory includes final E22 durable user content and compatible pre-writer decode. |
| A24 | Final #115 closure and E16/candidate preparation were circular prerequisites. | Canonical S/V/P sequence separates implementation stabilization, private proof and public approval; all acceptance retained. |
| A25 | Static graph checks, minimum-of-trials benchmarks or self-review could be mislabeled broader proof. | #115/#17 explicit evidence meanings, full samples/runtime sentinels and honest reviewer provenance. |

## Clarifications for retained hand-offs

**#79:** 'Evict a timed-out worker' means remove it from reusable admission, not pretend its process or memory ceased instantly. Retain draining accounting until termination/completion is observed; a stuck worker cannot trigger unlimited replacement workers. Its initial real-engine/context check is named DIAGRAM-CONTEXT in readiness.json. All three bundled harnesses must accept the actual structured palette safely; no invented engine option IDs. Neutral defaults do not guarantee arbitrary author-specified colors.

**#119:** The bounded snapshot/digest admission service is owned within FileCore and shared across its monitors/windows. It is not a dependency on Preview, DocumentPresentation or the LocalResourceAccess consumer layer. #121's contained-resource reader and FileCore's monitored authoritative document snapshots have different contracts; do not create a dependency cycle to call them one global reader. Preserve FileStore publication checks and explicitly revalidate lifetime after moving synchronous conflict reads off MainActor. Measure aggregate application load as well as each bounded service.

**#120:** The existing logical save token is operation identity, not a forever document ID. #18's CLI subscription follows a stable controller-owned document lifetime across successive Save As operations; it must not reuse one save attempt's token. The existing save-progress/close wording architecture otherwise stands.

**#88:** The retained engineering-versus-artifact separation remains required. Reconcile actual post-E22 command/focus behavior rather than retaining stale test expectations, and never run untrusted PR code in a privileged interactive signing/test environment.

**Export retirement threat boundary:** Quarantine is a private operation-owned staging namespace (owner-only directory, unpredictable exclusive names, validated descriptors), not a sandbox against arbitrary same-UID code intentionally modifying that private staging while the app owns it. No architecture can derive exclusive ownership merely from a hash-shaped name. Unknown/mismatched bytes are retained and reported; no blanket deletion. #118 must not claim filesystem compare-and-swap from a precheck plus rename. Its explicitly permitted overwrite behavior and any reused conditional-publication helper need precise tests; a newly required cross-module binary publisher is a focused architecture change, not an improvised implementation shortcut.

## Pass 4 — Dependencies, evidence and readiness

readiness.json contains 13 hand-offs, 48 dependency nodes and six named probes. Nodes include inputs/upstream work, implementation, probes, verification and release gates; they are NOT 48 new issues or a requirement for 48 PRs. Combine or split reviewable changes only without violating dependencies/ownership. Whole issue closure is separate from tested prerequisite availability.

The local static check initially rejected an incomplete inventory while the metadata was being authored; that omission was corrected before committing the manifest. The final check validates exact issue coverage, real hand-off filenames from the retrieved repository tree, unique unit IDs, known dependencies, acyclicity, probe inventory, preserved E22 ownership and S/V/P authorization edges. Its 13 positive/negative checks include omitted/duplicated issues, missing files/dependencies, a dependency cycle, removed public authorization, false runtime/independent-review claims and E22 reclassification. This is planning validation only.

Validated manifest SHA-256: `7a699ce616724e8a87a8ea56bcd38eca111eb507e69625eb0a1855851c69fa23`.
Expected Git blob: `98f0bcd14f4400f12484f76383c25bb5a1fa2583`.

From a checkout containing these files, run:

```sh
python3 planning/downstream/validate_readiness.py planning/downstream/readiness.json --self-test
```

The local container did not hold a full clone; its file-presence check used the explicit filenames returned by the GitHub tree, not fabricated placeholder files. Remote blob identity and final PR changed-file scope are separately checked. Do not report this as swift test, app build, CI, actual file migration or final gate validation.

## Six first-step probes — all NOT_RUN here

| Probe | Prerequisite and exact question | Dependent work |
| --- | --- | --- |
| RESOURCE-OPEN | Shipping SDK/minimum supported macOS: do real constrained opens reject outside-root leaf/intermediate/ancestor/root races while preserving admitted in-root cases and bounded reads? | #121 reader/integration and #118 resource consumption. |
| MATH-ADAPTER | Pinned real Textual/SwiftUIMath: do pre-admitted markers survive parser contexts and become accessible typed attachments with exact original spans, no escaped-dollar corruption or marker leakage? | #116 native math integration. |
| ANCHOR-PARSER | Actual pinned parser plus browser/WebKit fixtures: do authored-ID/entity/context inventories agree with unique emitted heading targets without rewriting authored HTML or imposing the old global cap? | #117 static/native anchors and shared presentation. |
| PDF-PRINT | Interactive Mac: does the proposed native print callback retain responsiveness, exact-once completion and truthful cancellation/disposal? | #118 PDF adapter integration. |
| DIAGRAM-CONTEXT | Real bundled Mermaid/D2/Graphviz harnesses: which verified options produce the chosen opaque neutral defaults consistently in native and vector outputs without relaxing security? | #79/E23 renderer integration and calibration. |
| QL-REPLY | Installed minimum-OS provider: actual permissions/reply factory/cid handling, cancellation and the ability to return precomputed fallback while expensive rendering drains. | #113 broad Quick Look integration. |

Each probe has positive controls, discriminating negative cases and a recorded decision output in its owning hand-off. Failing the probe requires a narrow revision before dependent work. It does not authorize new renderer ecosystems, broad entitlements, hidden API guesses or a lowered acceptance threshold. Successful source inspection is not a substitute for these executions.

## Per-issue implementation entry

| Issue | Ready entry once its prerequisites are met | Remaining acceptance gates |
| --- | --- | --- |
| #121 | RESOURCE-OPEN and pure capability/reader tests. | Probe, WebKit races/network/MIME, real Release preview. |
| #117 | Pure destination/index values and ExportOrigin snapshot. | ANCHOR-PARSER, actual links/navigation, measured parse cost, E22 registry result. |
| #116 | MathSyntax/source-exclusion and pinned dependency preparation. | MATH-ADAPTER, native accessibility/VoiceOver, parity/performance/exports. |
| #118 | Registered assembly/publication work after reader/snapshot prerequisites. | PDF-PRINT, resource/publication races, crash/size/memory and real UI/PDF proof. |
| #79 | Structured neutral context after E23 palette values. | DIAGRAM-CONTEXT and all-engine print/limits/lifecycle measurements. |
| #113 | Palette/catalog/read-only decoding after E22 interfaces; minimal QL-REPLY separately. | Probe/shared prerequisites, actual Finder/security/performance/artwork/identity. |
| #120 | Logical-save registry and explicit-origin panel tests. | Real close/save/Open UI and measured latency. |
| #119 | Bounded FileCore probe admission/lifetime regression work. | Full actual external-change matrix and Release measurements. |
| #88 | Isolated harness/test-plan and precise fixture/assertion repairs. | Suitable interactive Mac and final exact-artifact critical suite. |
| #53 | SETTINGS-COMPAT historical decoding first; then frozen-schema import map. | Final settings/theme inputs, actual consent/retry/live migration and E22 parser half. |
| #18 | Bootstrap/CLI/updater implementation after storage/identity prerequisites. | Credentials, genuine stateful signed update/Gatekeeper and P authorization. |
| #17 | Inventory/test preparation; final pass only after S. | Actual translation access/native review/plural/layout/non-English app proof. |
| #115 | Finite evidence-manifest/validator preparation. | S, final E16, all V exact-artifact obligations and separately authorized P. |

No issue is closed by this review. No public release or production branch merge is requested automatically. Claude should finish current E22, adopt the reviewed architecture through the normal PR process, rebind exact interfaces once, and execute the dependency-ready units with the named probes first. There is no blanket 'architecture is bug-free' claim and no concealed permission to mark blocked runtime evidence passed.
