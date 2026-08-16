# macOS 1.0 release-hardening contract

This document defines cross-cutting constraints for the existing macOS 1.0 roadmap. It does **not** add another epic or expand the feature set. It exists so E11–E21, the feature-complete gate, E15, E16 and E17 converge on one shippable product rather than satisfying their individual acceptance criteria in isolation.

The current epic product contracts remain authoritative for feature ownership. This document is authoritative where work crosses epic boundaries: identity freeze, offline/privacy behaviour, derived-content reuse, release evidence, text fidelity, update migration, localisation freeze and release-candidate validation.

## 1. Product invariants

### 1.1 Local and offline by default

Opening, editing, saving, Markdown preview, first-party math, supported first-party diagrams and HTML/PDF export must work without an internet connection.

Document content is not transmitted to a hosted renderer or other external service as part of normal first-party functionality. A future network-backed feature would require an explicit product/security decision and clear user consent; it must not appear as an implementation shortcut inside E19–E21.

Third-party executable text filters are explicitly user-installed local commands and are not first-party document rendering.

### 1.2 Text remains the durable source of truth

Markdown, code, TeX source and fenced diagram source remain readable text on disk. Preview artefacts, rendered equations, SVG diagrams and caches are derived and disposable.

A missing renderer, failed render, cache corruption or future renderer-version change must never replace or destroy the authored source.

### 1.3 No silent file normalisation

Opening and saving a file must not gratuitously rewrite encoding, byte-order mark, line endings, final-newline state or unrelated text merely because the editor touched the document.

Where an explicit conversion is necessary or user-requested, the behaviour must be deliberate and testable rather than incidental to a String round-trip.

## 2. Shared derived-content architecture

E12 and E14 must establish one path that later math and diagram features can reuse.

Conceptually:

```text
source / parsed source
  -> first-party contribution or renderer
  -> derived representation + diagnostics + stable source identity
       -> Preview presentation
       -> HTML/PDF export
       -> copy/export action where supported
```

### 2.1 E12 responsibility

E12 owns the export destination contract. It must make it possible for later first-party derived content to contribute exportable output without inventing a second complete export pipeline.

E12 does **not** implement math or diagrams. It provides the export-side extension point, document/template composition rules, asset handling and failure semantics that E19/E20/E21 later consume.

### 2.2 E14 responsibility

E14 owns the first-party contribution lifecycle and isolation model. Its core contribution result must not be defined only as a SwiftUI preview view.

The contract should expose renderer-neutral derived content/diagnostics/source identity, with Preview and Export acting as consumers/adapters. UI-specific SwiftUI views may exist at the Preview edge, not as the only durable contribution representation.

This requirement prevents E19/E20 from building one renderer for live preview and a separate unrelated renderer for export.

## 3. Text-filter command safety baseline

E14's executable text filters are powerful local tools and require a fixed minimum safety contract:

- launch an executable with structured arguments; never build a shell command by interpolating document text or file paths;
- define the working directory deliberately;
- expose only documented environment variables rather than inheriting an unrestricted environment accidentally;
- bound execution time and support cancellation;
- bound captured stdout/stderr so a command cannot exhaust memory;
- preserve the original selection/document if the command exits non-zero, times out, is cancelled, produces invalid replacement output or otherwise fails;
- make failure visible and understandable without losing editor state;
- ensure a hung filter cannot hang the app's main actor;
- distinguish user-installed commands clearly from first-party built-in features.

Exact limits belong to the current-master E14 architecture pass; the behaviours above are non-negotiable.

## 4. Renderer admission gate for E21

E21 evaluates D2, Graphviz/DOT and WaveDrom individually. Mentioning a renderer in the roadmap does not require shipping it if the implementation review shows that it is a poor macOS 1.0 dependency.

For each renderer, the architecture pass records an **accept** or **reject** decision based on:

- licensing and redistribution terms;
- local/offline execution;
- security/trust boundary;
- runtime and package/bundle-size cost;
- startup impact;
- cancellation and failure isolation;
- vector/export quality;
- accessibility possibilities/limitations;
- maintenance health and integration complexity.

Accepted renderers satisfy the common E20 user experience. Rejected renderers remain text fences with a clear unsupported/capability state if encountered; rejection is not an E21 failure when the evidence and rationale are recorded.

E21 must not weaken E20's renderer abstraction merely to force every candidate to ship.

## 5. Feature-complete gate

The feature-complete gate occurs after all planned macOS 1.0 feature work through E21 and before E15 polish.

It has four additional responsibilities beyond checking whether feature epics are closed.

### 5.1 Freeze public identity

Before E15 begins, freeze:

- final public product name;
- bundle-identifier strategy;
- CLI public command/name where affected;
- repository/public-link strategy;
- appcast/update-channel identity;
- Application Support / preferences / recovery namespace migration strategy from development identifiers.

E15 then creates the final icon, first-run experience and polished copy against this identity. E16 localises stable identity-bearing strings. E17 implements/verifies the already-approved release identity; it does not decide the brand at the end of the release cycle.

### 5.2 Maintain a release-evidence ledger

Create one owner-readable table for the complete product. At minimum:

| Capability/epic | Implementation complete | Automated evidence | Real-app/Release evidence | Manual evidence | Open P0/P1/P2 | Release status |
|---|---|---|---|---|---|---|

Closed issues and green package tests are inputs to this ledger, not substitutes for release evidence.

Known evidence debt from earlier epics must appear explicitly rather than being forgotten because implementation issues are closed.

### 5.3 Execute critical UI tests

Critical XCUITests must actually execute on a real/suitable macOS 26 environment before 1.0. `build-for-testing` is not equivalent to a passed UI test.

If hosted CI cannot execute the required UI suite, record a repeatable local-Mac release command and its result. Unavailable test rows are marked unverified; they are never inferred as passed.

Critical coverage includes document lifecycle/recovery, native tabs/session restore, editor interaction, preview publication/navigation, external-file conflict behaviour, format transitions and other release-blocking UI journeys introduced by later epics.

### 5.4 Prove text round-trip fidelity

The release corpus must exercise at least:

- UTF-8 and every intentionally supported alternate encoding;
- files with/without byte-order marks where relevant;
- LF and CRLF line endings;
- Unicode including emoji and CJK text;
- files with and without a final newline;
- no-op open/save where document bytes should remain semantically/byte stable according to the format contract;
- large files;
- Save As / format transitions;
- external formatter/Git-style atomic rewrite while open.

Any deliberate normalisation must be documented and user-safe.

## 6. E15 product-completion responsibilities

E15 is not only visual polish. After the feature-complete gate it owns the final coherent first-run and whole-app experience.

E15 should finalise the welcome/first-run/sample-document UI and any new user-facing onboarding copy before E16's string freeze. E17 may package and verify that flow but should not invent a new first-run screen after localisation.

E15's whole-app pass consumes the release-evidence ledger and closes release-blocking integration defects. It does not mark unknown evidence as passing.

## 7. E16 string freeze

E16 runs after the final public identity and first-run/product UI are stable.

Once E16 reaches string freeze:

- E17 may update release notes, website copy and other non-app release material;
- E17 must not introduce new user-facing app strings or new app UI without reopening the affected localisation verification;
- emergency wording fixes require updating String Catalogs and re-running the relevant localisation/pseudo-localisation checks.

This avoids shipping an English-only release screen after the localisation epic is considered complete.

## 8. E17 update and identity migration gate

E17 must test more than a clean installation and an empty-state Sparkle update.

At least one release rehearsal starts from a previously installed development/beta build containing representative real state:

- preferences/settings;
- recent roots or workspace state;
- restored windows/tabs/session data;
- file bookmarks/URLs where applicable;
- untitled recovery buffers;
- caches that may safely be discarded;
- old development-name Application Support/defaults locations if the final identity changes them.

Then update/install the release candidate and prove that authoritative user state is preserved or deliberately migrated. Disposable caches may be rebuilt.

The migration must be idempotent and recoverable enough that a failed/partial identity migration does not silently discard user-authored recovery data.

Two consecutive signed release-candidate builds must still pass the normal Sparkle N -> N+1 signature/update test.

## 9. Defect severity at release gates

Use a simple release classification so the feature-complete gate and E17 do not rely on vague judgement:

- **P0** — crash, data loss/corruption, security boundary failure, cannot launch/open/save/restore/update: blocks release.
- **P1** — core editor/preview/export/workspace/math/diagram path materially broken or misleading with no reasonable workaround: blocks release.
- **P2** — significant visible or workflow defect with a practical workaround: fix or explicitly accept with an owner-readable record.
- **P3** — minor cosmetic/documentation issue: may defer with a record.

No P0/P1 may remain for macOS 1.0.

## 10. E11 architecture reconciliation

The existing E11 architecture PR predates the 2026-08-16 product-contract changes. Before E11 implementation work uses it as a binding contract, it must be refreshed against:

- the current `master` baseline;
- the revised E11 issue including TeX/LaTeX source support;
- `planning/EPIC_STANDARD.md`;
- this release-hardening contract;
- any relevant open format/preview follow-up issues.

An architecture PR that was correct against an older product contract is not grandfathered in automatically.

## 11. Scope discipline

This hardening contract does not add search-in-folder, Git status, multi-root workspaces, full LaTeX compilation, visual diagram authoring, PlantUML/TikZ, a renderer marketplace, Mac App Store work or iPad implementation to macOS 1.0.

Those remain outside the current roadmap unless a later explicit product decision changes scope. The purpose here is to make the existing plan integrate and release cleanly, not to make it larger.
