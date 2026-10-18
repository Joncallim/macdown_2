# MostlyText open-issue acceptance register

## Owner summary

MostlyText has 22 open issues. The integration candidate is locally preserved on
`fix/ci-timing-contracts`; it is not approved for merging or release. The immediate
work corrected timing assertions, restored the original whole-call cleanup bound,
retired a leaking benchmark window and corrected actor isolation in test suites.
The final code still has failed Release parser and editing-assist performance
measurements. Separate source review found no concrete regression, with explicit
coverage limits; owner acceptance remains pending. The
highlighting cutoff and production dependency pins remain unchanged. Editors
retain the existing reduced-highlighting behavior and the previously integrated
repaint correction. No new product capability is claimed.

This register connects every open issue to its remaining outcome and next bounded
step. It is an intake and execution map, **not** a completed closure audit. The
[criteria snapshot](downstream/open-issue-criteria-2026-10-18.json) preserves all
285 issue-body checkbox entries, source checkbox states, issue/comment dates and
content hashes. Prose requirements and comments remain binding; unchecked boxes
are not evidence of absent code, and checked boxes are not evidence of final
verification. Raw issue bodies and all comments are retained with the local logs.

Source inspected: `0b85e6f09dc3bba82a0da3b15f1583b3263fcb74`, based on clean
integration `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`. Master remains
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`; dependency experiments remain isolated
on `dep-trial` at `29e08843325bd744fb2cd5ea5abccf96dc22fb57` (the later handoff-only
commit acknowledges transfer of the integration worktree). The new local
changes have no hosted CI result. See the [timing investigation](downstream/evidence/ci-timing-2026-10-18/README.md)
and the [follow-up validation](downstream/evidence/ci-timing-2026-10-18/FOLLOWUP.md)
for exact-head outcomes and unresolved failures. The later
[independent review and fixed diagnostic](downstream/evidence/ci-timing-2026-10-18/INDEPENDENT_REVIEW.md)
cover documentation checkpoint `e16be9f7`, whose code matches `0b85e6f0`.

The subsequent [Mermaid artifact audit](../compliance/evidence/mermaid-11.17.2/README.md)
started at `40b25974`. It closes the missing bundle/source-map linkage and records
mapped modules and captured package texts, with independent review. It remains
partial for nested attribution, does not change distributed notices or product
code, and does not supersede either failed performance measurement.

The following [#53 reconciliation](downstream/evidence/settings-53-2026-10-18/README.md)
starts from `d3cc8883`. It fixes the reproduced distinction between an absent
status-bar field and explicit JSON null, and adds declaration coverage for the
legacy key table. An isolated probe also proves remaining write-protection gaps:
only the first unreadable Data generation is backed up, and non-Data values are
not reported. This is not completed migration or a waiver of #53's criteria.

The subsequent [#121 callback correction](downstream/evidence/preview-121-2026-10-18/README.md)
starts from `a4c48bc7`. It binds callbacks to their navigation/view and separates
queued attempts from process recovery. Retained baseline and review regressions,
negative controls and a simple real WebKit render support that bounded fix.
Mutable resource-root confusion and post-stop delivery were also reproduced and
remain open; no resource-authority or full native release claim follows.

## Evidence rules

- **Source:** implementation or a gap inspected in this candidate. This alone
  does not prove the user journey.
- **Local:** command, environment, exact commit and outcome recorded together.
  Mutation failures are negative controls, not passing validation.
- **Hosted:** GitHub's actual tested checkout, including its synthetic merge
  commit, is recorded. Local passes do not overwrite hosted failures.
- **Native/manual:** the real window/input method/artifact and exercised path are
  named. Building a UI test does not execute it. The Simplified Pinyin evidence
  is Debug-only and does not establish automated CJK coverage.
- **Historical:** older observations remain useful but are not relabelled as
  proof for this candidate. Independent review and owner acceptance stay distinct
  from an author's tests or source inspection.

## Every open issue

| Issue | Current evidence and remaining outcome | Next bounded step |
| --- | --- | --- |
| [#17 Localization](https://github.com/Joncallim/macdown_2/issues/17) | Package-localized file-operation errors use the module bundle in inspected source. Final resource audit, French/Japanese native review, plural/layout checks and string freeze remain unverified. | Follow the E16 handoff after private candidate 1; retain a small current-source string/resource inventory before changing catalogs. |
| [#18 Distribution and migration](https://github.com/Joncallim/macdown_2/issues/18) | Release scripts exist, but the inspected project still uses development identity/version and CLI `macdown2`. Final migration, updater, install/update rehearsal and exact signed artifacts remain open. | Rebaseline application-side architecture against final settings/themes and frozen MostlyText identity. Prepare locally; signing, notarisation and publication are explicitly outside current authorization. |
| [#53 Preferences and Markdown options](https://github.com/Joncallim/macdown_2/issues/53) | Missing-field compatibility was already implemented; explicit null is now rejected after a baseline reproduction. A source-pinned record/checker covers 52 stored, four calculated and two transient legacy declarations, with six unproved destination candidates. Isolated evidence shows future primary data is replaced on ordinary save, a second unreadable generation can be lost, and non-Data objects are not reported or retained. | Reconcile the shared protected-writer admission/recovery contract before changing setters or adding import execution. Complete conversions, precedence, consent, idempotence and E23 destinations; declaration coverage alone cannot close this issue. Use isolated fixtures only. |
| [#79 Diagram appearance](https://github.com/Joncallim/macdown_2/issues/79) | Integration uses a neutral-light presentation. PRs #476/#477 offer theme-dependent alternatives; D2, print/PDF contrast and the cross-engine policy still need reconciliation. | Recommend retaining the neutral representation until the owner accepts an explicit policy compatible with E23 and #79. Compare alternatives without merging conflicting behavior. |
| [#88 Native UI coverage](https://github.com/Joncallim/macdown_2/issues/88) | Historical native passes and the bounded Simplified Pinyin manual record exist. Final E22/E23 critical flows, other input methods, candidate mouse interaction and long composition during restore are not proved. Six UI suites and two app-test suites now have corrected actor isolation; the final app-owned compiler commands pass with Swift warnings treated as errors. Native UI execution remains unverified on this code. | Freeze the actual final software candidate, then execute the finite critical UI matrix in an explicitly available desktop session. |
| [#112 Editor essentials](https://github.com/Joncallim/macdown_2/issues/112) | Much of E22 and subsequent hardening is implemented. Its performance, settings, recovery, native interaction and audit acceptance is not complete merely because feature code landed. | Reconcile each E22 criterion with #183 and the dependency-specific records; repair one reproducible gap at a time with negative controls. |
| [#113 Themes, Quick Look and Finder](https://github.com/Joncallim/macdown_2/issues/113) | Two bundled Tomorrow themes exist; the inspected XcodeGen spec has no Quick Look target. The full theme set, safe custom themes, shared static presentation and Finder integration remain product work. | Rebaseline the post-E22 architecture using frozen identity inputs and the safe resource/anchor contracts; satisfy Definition of Ready before broad implementation. |
| [#115 Debt gate](https://github.com/Joncallim/macdown_2/issues/115) | Umbrella release acceptance remains open. Older package/app/UI passes are historical, not a substitute for all owning issues or exact-artifact proof. | Follow software stabilization → private candidate 1 → final localization → candidate 2 and artifact-sensitive reruns. No administrative closure on CI alone. |
| [#116 Math correctness/accessibility](https://github.com/Joncallim/macdown_2/issues/116) | Scanner/contribution components exist. Complete syntax/escaping, diagnostics, equation-level navigation, accessible equations and native visual/performance/parity proof remain. | Follow the math handoff: discriminating syntax cases and adapter probe before integrating presentation behavior. |
| [#117 Contributions, anchors and palette](https://github.com/Joncallim/macdown_2/issues/117) | Generic representations exist, preview admission still rejects HTML, and TOC output is plain text. Shared anchors, clickable destinations, capability policy, palette consistency and explicit export targeting require complete evidence. | Execute shared anchor/parser capability probes; update the accepted contract before changing preview/export consumers. |
| [#118 Export safety and fidelity](https://github.com/Joncallim/macdown_2/issues/118) | Export infrastructure exists, but current-source coverage is not a complete closure audit. F06/F13 output-authority cases, resources, parity, real PDF print behavior, budgets, cancellation and recovery remain required. | Reconcile the export handoff against source, then prove one opened-resource/output-publication boundary with hostile schedules before broad refactoring. |
| [#119 External-file evidence](https://github.com/Joncallim/macdown_2/issues/119) | Existing automated coverage does not supply the full native external-change matrix or Release watcher/digest/latency measurements. | Run the documented Release manual/performance matrix with independent byte reads, selection/scroll observations and watcher/wakeup evidence on the chosen candidate. |
| [#120 Open/Save interaction](https://github.com/Joncallim/macdown_2/issues/120) | Source has saving state and a destination-aware close-sheet label. End-to-end Save As progress, changing backing-file state and large-file Open latency remain unverified. | Exercise native Save As/close paths and measure Open before deciding whether another code fix is required. |
| [#121 HTML preview authority](https://github.com/Joncallim/macdown_2/issues/121) | Safe local-resource opening stage A and MIME handling exist. Exact navigation/view callback ownership and queued retry/recovery ordering now have local regression and simple native-render evidence on a293e397. A delayed task reading the wrong root and delivery after reentrant stop were independently reproduced and remain open. | Reconcile immutable per-load contexts and task registry with the retained root/stop controls. Bound worker/payload ownership and I/O, document/Save As identity, scope cleanup and the full native hostile corpus before closure. The coordinator correction alone does not resolve this issue. |
| [#148 Licensing/provenance](https://github.com/Joncallim/macdown_2/issues/148) | Mermaid's shipped bytes now match the official archive/map, with exact parser links, 72 versioned-map/parser records, two content-matched candidate versions and 74 captured package texts. Deeper prebundle attributions and 3,980 unmapped parser positions remain unresolved. Inventory/notices/SBOM remain unchanged; the eight release-preflight requirements and exact signed-artifact check remain open. The font KEEP decision is already recorded. | Trace the concrete KaTeX/React, Cytoscape borrowed-code and Rough.js prebundle attributions, resolve candidate-version limits, then install the complete inventory/texts/notices/SBOM together. Keep D2/Graphviz preparation and Tomorrow Light's E23 decision separate. Specific authorization is required before source-only publication. |
| [#155 Test hangs](https://github.com/Joncallim/macdown_2/issues/155) | Later discussion and #421 identify AppKit window animations exhausting dispatch workers in a reproduced schedule. This is stronger than the stale issue title, but does not explain every WebKit hang. | The later 103.099-second close delay has a reproduced contributor: the cache benchmark retained its real window and background work. A teardown regression fails without retirement; the final full-run close case takes 0.601 seconds. Investigate the remaining AppKit/SwiftUI update warnings and audit other fixture windows before a bounded native soak. This does not close every hang criterion. |
| [#158 Identity/cutover](https://github.com/Joncallim/macdown_2/issues/158) | MostlyText name, bundle prefix, CLI name, brand assets and MIT choice are frozen. Runtime migration and final repository/public-copy cutover are separate pending work. | Consume frozen inputs in E17/E23. Keep the full-history repository mirror late, after #115; do not rename or transfer the backlog early. |
| [#159 Fixture ownership](https://github.com/Joncallim/macdown_2/issues/159) | Integration contains typed readiness and bounded fixture ownership. The initial cleanup-only measurement was too narrow. Final tests restore the original 150 ms whole-call assertion for the zero-delay case, add separate phase diagnostics and fail a slow-setup negative control. Separate source review found no regression. Hosted overruns still have no established causal explanation. | Obtain owner acceptance and authorized hosted validation, and reconcile PR #473 against integration before closure. |
| [#173 Native navigation](https://github.com/Joncallim/macdown_2/issues/173) | Native activation already exists; the integration work adds lifecycle/currentness protections. PR #474 is an alternative with overlap, not an automatic missing feature. | Verify actual visible reveal below the viewport, tab activation and stale asynchronous intent on the native app; compare alternatives before adopting one. |
| [#183 Merged-code audit](https://github.com/Joncallim/macdown_2/issues/183) | Many original findings have subsequent fixes, while `CLOSURE_REGISTER.md` still records partial safety families and native/fault-injection gaps. Old source findings must not be reported as current without rechecking. | Build criterion-to-source/test/native mappings for F01–F23 and later review additions; take the first still-reproducible bounded defect, preserving exact scalar and lifetime invariants. |
| [#203 Large Markdown latency](https://github.com/Joncallim/macdown_2/issues/203) | The 8,192 UTF-16 fallback contains known stalls by reducing highlighting. It does not satisfy the original fully highlighted 1 MB budget. Dependency experiments remain isolated and unadopted. The second final planned Release series run failed the direct 1 MB parser ceiling at 484.814584 ms versus 400 ms; its cause remains unestablished. | Keep the cutoff/pins. Continue the measured grammar/dependency investigation only under its reviewed contract; verify edits and correctness before any adoption. Keep open. |
| [#459 Highlighting correctness](https://github.com/Joncallim/macdown_2/issues/459) | Debug abort/edit-geometry defects and some corrections are documented. Disabling assertions in Release is not proof of correctness; mounted lifecycle/stale-token and Unicode evidence remains incomplete. | Reconcile the proposed architecture in PR #462 and the dependency experiment with current integration; reproduce the remaining schedule on real Debug and Release editors before changing dependencies. |

## Sequence and concrete review gates

1. **Finish this integration checkpoint.** Separate source review through
   `e16be9f7` found no concrete regression. Preserve the failed Release parser
   ceiling and subsequent 56.881709 ms editing-assist result against 50 ms; the
   fixed context experiment stopped on that new failure without proving a cause.
   Address remaining runtime/build-tool diagnostics and owner acceptance, then obtain
   authorization to push the reviewed branch for fresh hosted CI. The exact proposed
   external change is a fast-forward of remote `integration-final` from `60f779fc`
   to the accepted local tip; it has not been performed. PR #480 stays draft/unmerged.
2. **Complete remaining E22 and safety work in small slices.** Prefer #121's
   already-documented request-lifetime slice and discriminating #183 regressions;
   do not treat the architecture-readiness graph as implementation evidence.
   Rebaseline the relevant handoff before any changed cross-module dependency.
3. **Complete dependent product work.** Settings compatibility precedes migration
   writers; the theme and shared resource/anchor contracts precede E23 consumers.
   Implement E17 application behavior before software stabilization. Keep native
   evidence tasks alongside the code they assess.
4. **Follow the adopted two-candidate sequence.**
   [RELEASE_SEQUENCE.md](RELEASE_SEQUENCE.md) supersedes older single-candidate
   sequencing in issue prose and old status paragraphs. It does not waive their
   acceptance requirements. #115 remains open through final localization and
   final-artifact compliance/reruns; repository cutover and public promotion are
   later, separate authorizations.

The seven current release-preflight failures are: D2 anonymous source location;
D2 Go and embedded-WASM license/source inventory; Mermaid bundled npm provenance;
Tomorrow Light naming/provenance decision;
Viz/Graphviz anonymous source location; exact Graphviz 16.0.0/Viz 3.30.0 source,
build instructions and hashes; and Graphviz-linked library confirmation.
The [2026-10-18 font reconciliation](../compliance/evidence/swiftui-math-fonts-2026-10-18/README.md)
records the existing KEEP-all-12 decision and retains all resource and licence
checks. Historical eight-failure evidence remains unchanged.
The generated, ignored `MacDown2/MacDown2/Info.plist` makes the working-directory
compliance scan report an unregistered distributed file. The clean `git archive`
source scan passes. This distinction is recorded rather than deleting or
registering a generated artifact to silence the check.

Recommended owner choices are concrete: retain neutral diagram presentation
until a reviewed cross-engine/print policy is accepted; preserve the 8,192 cutoff
and current lock while dependency correctness is unresolved; retain all currently
licensed fonts, following the KEEP decision already recorded in
[#148 comment 5868785863](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5868785863)
and now reconciled in `compliance/inventory.json`; and reconcile the
Tomorrow Light name with the recorded asset provenance rather than assuming a
name grants provenance. The font choice was already recorded; the other
recommendations do not adopt new policy.

## Branches and evidence to preserve

PRs #473/#474/#476/#477 overlap or conflict with integration and need deliberate
comparison. PR #475's change is already represented in integration history.
PR #472 is superseded evidence, but any external closure waits until integration
is accepted. PR #462 remains proposed architecture. The unmerged Pinyin UI branch
`4cc7a2622bab65213932e7164577562dbeaaae6a` is preserved; manual Pinyin evidence
has narrower coverage than automated input-method proof.

No issue was closed, no PR was changed, and no branch was pushed by this checkpoint.
No signing, notarisation, credential work, source/binary publication, upstream
submission, worktree deletion or repository cutover is authorized here. The owner
review remains pending. Separate source review of the local corrections through
`e16be9f7` is complete; it does not replace the failed performance or release gates.
