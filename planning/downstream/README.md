# Downstream architecture hand-offs

Reviewed source baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09` on 2026-09-24.

Documentation branch: `docs/downstream-architecture-2026-09-24`.

## Start here, after the current Epic 22 work

These documents cover all **13 open issues outside Epic 22** in the reviewed inventory. They are implementation hand-offs, not completed implementations, test results or release authorization. Each issue has its own source reconciliation, chosen ownership/data flow, lifecycle and failure rules, verification matrix, allowed changes, stop conditions and architecture self-review.

**Continue Epic 22 under its existing plan.** This branch changes no application code, existing plan, catalog, project configuration or workflow. It does not change #112, PR #124, its branch/reviews/CI, or the next E22 slices. In particular, #53's inert-parser-option work and #117's command-registry work remain with E22; the downstream plans consume those outcomes rather than supply competing implementations.

When reaching downstream work, read the relevant hand-off and its named shared dependencies. Reconcile the exact then-current master, live issue amendments and completed E22 interfaces before changing code. The reviewed baseline is not a claim that master will remain unchanged. Rebind renamed interfaces; do not undo completed E22 work to match a proposed symbol here. Semantic type names in these plans are proposed interfaces unless identified as existing code.

## Issue index

| Issue | Hand-off | Implementation focus |
| --- | --- | --- |
| #121 | [HTML Preview isolation and contained reads](issue-121-handoff.md) | Immutable WebKit load ownership, race-resistant descriptor reads and exact-once task teardown. |
| #117 | [Contribution destinations, anchors and export identity](issue-117-handoff.md) | One heading/TOC policy, authored-ID collision handling, explicit command origin and immutable export snapshot. E22 retains registry ownership. |
| #116 | [Math correctness and accessibility](issue-116-handoff.md) | Shared delimiter grammar, narrow pinned dependency adaptations, structured diagnostics, equation accessibility and source navigation. |
| #118 | [Bounded HTML/PDF export](issue-118-handoff.md) | Final assembled-byte limits, managed-asset recovery, destination ownership, operation progress and safe PDF cancellation/publication. |
| #79 | [Diagram presentation coherence](issue-79-handoff.md) | E23-owned neutral diagram canvas, actual render parameters, cache identity and measured print/render limits for all three engines. |
| #113 / E23 | [Themes, Quick Look and Finder integration](issue-113-handoff.md) | Semantic palettes, safe theme catalog, shared static presentation, least-privilege Quick Look and finalized icon/identity. |
| #120 | [Save As progress, close prompts and Open latency](issue-120-handoff.md) | Logical save operations across document-ID changes, truthful stable prompts, explicit panel origin and measured latency. |
| #119 | [External-file behavior and watcher evidence](issue-119-handoff.md) | Complete real-file/UI matrix, bounded probe admission, handle/callback teardown and Release measurements. |
| #88 | [Interactive UI and exact-artifact verification](issue-88-handoff.md) | Repair the three remaining historical UI paths; repeatable engineering and final-artifact lanes with no false skip/build-only passes. |
| #53 | [Legacy MacDown preference import](issue-53-handoff.md) | Complete declared-key disposition, explicit consent, destination precedence and restart-safe import. E22 retains parser cleanup. |
| #18 / E17 | [Migration, CLI, updates and distribution](issue-18-handoff.md) | Bootstrap/namespace preservation, open/stdin/--wait, pinned Sparkle integration, signing and stateful update rehearsal. |
| #17 / E16 | [Final localization and string freeze](issue-17-handoff.md) | Complete resource/string audit, validated Transifex round trip, plural/native-language/layout QA and a hash-bound freeze. |
| #115 | [Finite debt closure and release proof](issue-115-handoff.md) | Per-obligation evidence, fresh whole-repository review and an executable exact-artifact release gate. |

## Shared contracts: implement once

#121 owns **LocalResourceAccess**. Export consumes the same opened-object read boundary; Quick Look consumes only the authority actually granted to its request. A source-file grant never implicitly becomes a directory grant.

#117 owns **HeadingAnchorIndex**, contribution destination semantics and **ExportSnapshot/origin**. #118 extends that same export operation with progress, destination leases and publication. E23's **DocumentPresentation** orchestrates these existing components rather than creating a second cmark, anchor, contribution or resource pipeline.

#116 owns **MathSyntax** and the narrowly adapted dependency boundary. E23 consumes its actual math result/accessibility interfaces, not a copied tokenizer or a second LaTeX validator.

E23 owns the semantic palette and theme catalog. #79 is one implementation unit within that ownership, not an independent competing theming system. Its chosen 1.0 diagram policy is neutral light artwork with readable defaults, not arbitrary recoloring of authored styles.

#120 owns logical-save progress and panel-origin behavior. #119 consumes the completed editor/save interfaces for external-file evidence. #88 owns reusable interactive verification infrastructure. None of these rewrites FileStore's conditional publication or recovery authority.

#53 owns legacy preference conversion. E17 owns application bootstrap and development-namespace migration; legacy import and development-state preservation are separate tested journeys. E16 owns final language sign-off after all in-app release work has contributed its strings.

## Dependency order, not a new immediate work queue

After E22 and the identity/interface reconciliation, prepare #88's verification harness and the shared foundations: #121's reader, #117's anchors/snapshot, #116's math boundary, and E23's semantic palette. #120's save-operation work and #119's bounded monitor/probe work are separate units with their own regression coverage.

Integrate #118 against the shared reader/snapshot, and complete #79 inside E23's palette work. E23 then integrates the theme catalog and Quick Look/static presentation against those proven contracts. Do not wait for an entire umbrella issue to close when a tested prerequisite unit is sufficient; equally, a tested prerequisite does not close its owner's remaining acceptance criteria.

Once final settings/themes exist, implement #53 and E17's application-side bootstrap, CLI and updater, including their normal catalog entries. Finish all product fixes and engineering checks before the final E16 pass. Keep final public release promotion separate from engineering and private evidence preparation.

## Resolve the release sequencing loop explicitly

The #115/#17/#18 hand-offs specify a shared **S / V / P** amendment which must be reconciled in the canonical release documents before execution. This branch does not silently amend those live contracts.

**S — software/UI stabilized:** required fixes and all application-side release code/strings are present. #115 remains open awaiting final proof. This milestone is E16's prerequisite.

**V — final localization and private verification:** E16 freezes the final surface; E17 prepares private, unapproved signed/notarized artifacts for genuine UI, VoiceOver, export, Quick Look and stateful update proof. No public RC, stable-feed entry or production approval is permitted.

**P — authorized promotion:** #115 closes only after its complete matrix passes. The separately authorized release promotes the same verified bytes, not a rebuilt or re-signed substitute. Changed artifacts/strings/identity invalidate affected evidence.

## Review and evidence boundaries

Per-issue reviews and the cross-contract pass addressed stale request/root ownership, resource-size amplification, Save As identity gaps, ambiguous raw HTML heading IDs, protected preference values, detached work that outlives cancellation, skipped native tests and evidence tied to the wrong binary. The #117 hand-off received a corrective commit selecting one authored-ID reservation policy rather than leaving alternatives for the implementer.

This is architecture-level review, not independent native execution or proof that all possible defects have been eliminated. Numerical limits labelled proposed/initial are defensive design values requiring the specified calibration; they cannot silently replace existing owner-approved performance budgets. No issue is closed by these documents.

Required implementation-time facts remain explicit: supported-SDK/minimum-OS contained-open behavior; real Quick Look reply/attachment and sandbox grants; AppKit print/cancellation behavior; actual interactive/VoiceOver/GUI proof; frozen technical identity and approved final artwork; native-speaker review and authorized Transifex/signing infrastructure. Do not infer any of them from a code build or this review. A failed platform probe is a precise stop condition, not permission to weaken security or fabricate passing evidence.

Use the project's serial validation discipline, follow the issue's acceptance matrix, and record genuine as-built/evidence deltas with each implementation unit. Keep public publication, issue closure and production approval behind their actual gates.
