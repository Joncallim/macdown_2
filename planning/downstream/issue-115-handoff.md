# Issue #115 — Finite debt closure and exact-artifact proof

## Owner summary

Close the promises already made, prove the finished application and stop treating green package tests or old epic closure as release approval. This is a finite hardening/evidence gate, not another feature epic or a new historical-debt hunt. Its output is an auditable go/no-go decision for one exact release artifact.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, reviewed 2026-09-24. Leave Claude's E22 implementation entirely alone. Consume its eventual completed evidence along with E23 and the issue-specific hand-offs in this directory. This document supplies no runtime PASS, closes no issue and grants no release authorization.

## Reconciled authority

Read the live #115 body, both 2026-09-21 checkpoint comments, RELEASE_HARDENING and the release ledger's current header/audit. The final historical search was already completed and reconciled at master f7080338951860bd823f2d3b8164360d40733254 through PR #122. PR #114's planning/as-built reconciliation is already merged. Do not reopen these completed searches or manufacture new issues from old words such as 'deferred' without checking their current disposition.

The finite capability closure set is #53, #79, #88, E22 #112, E23 #113 and #116–#121. E16 #17 and E17 #18 supply final localization/distribution evidence. Existing non-goals remain non-goals: full TeX compilation, generic third-party plugin loading, interactive Mermaid click features, visual diagram authoring and iPad. WaveDrom is explicitly rejected for 1.0; it does not remain an unresolved renderer promise.

## Explicit sequencing reconciliation

The current wording contains a real dependency loop: the #115 final matrix requires final E16 and exact signed candidate evidence; E16 follows #115's software/UI debt closure; E17 must not authorize a production RC while #115 is open. Resolve the vocabulary before execution rather than dropping a check.

Adopt the following precise amendment in the canonical #115/E16/E17/hardening documentation as one later documentation change. This isolated hand-off does not itself edit those live contracts:

1. **S — Software/UI debt stabilized.** E22/E23 and the required product fixes, including E17's application-side migration/CLI/updater and their user-visible strings, are implemented and engineering-verified. The current source/identity/UI is frozen for final localization. #115 remains OPEN because final proof is not complete. This milestone, not issue closure, is E16's prerequisite.
2. **V — Final localization and private verification candidate.** E16 completes native-language, plural, extraction and layout QA. E17 produces a private, unapproved signed/notarized candidate and update-rehearsal artifacts solely for required evidence. #88 and this gate exercise the exact immutable bytes. No public RC/stable appcast entry, production approval or release announcement is allowed. Missing permissions/credentials/QA keep V incomplete.
3. **P — Production authorization and promotion.** Only after every required #115 row and final E16 record passes may #115 close and the owner/release process authorize public promotion. Promote the SAME V artifact; do not rebuild/re-sign it after proof. Thus the final public RC is the exact signed artifact that passed verification. Changed bytes, identity, entitlements, strings, source or failed final checks invalidate the relevant proof and reopen the gate.

This preserves the issue's hard production-authorization precondition and its exact-artifact requirement. A private verification build is never described as an authorized production RC. The amendment must explicitly replace ambiguous 'after #115' references with S or P as appropriate; do not leave two contradictory checklists and rely on agent interpretation. No required test is downgraded to 'manual later' to break the loop.

## Evidence model and ownership

Add a versioned machine-readable current gate manifest alongside the owner-readable ledger, with immutable historical evidence records. Separate obligation state from execution state. During work a result may truthfully be NOT_RUN/RUNNING/BLOCKED/FAIL; none permits closure. Final required dispositions are exactly FIXED with passing evidence, PROVED with passing evidence, or REJECTED_FOR_1_0 only where the original optional-feature contract allowed rejection.

Each obligation record contains a stable ID, original issue/epic/source paragraph, exact behavior, required evidence kinds, current owner, code/contract baseline, severity, applicability rationale, current disposition and evidence references. Each evidence record contains run ID, source and test-driver SHA, app artifact identity/hash/CDHash, dependency/toolchain/OS/hardware, fixture hashes, command/test selection, actual discovered/executed/passed/failed/skipped cases, result-bundle/log/artifact hashes and a named manual reviewer where applicable.

Evidence references point to retained readable artifacts, not an expired /tmp path or an unsupported 'tested locally' sentence. Scrub unrelated personal data, signing tokens and real document contents. Preserve failed and superseded runs. A hash establishes the identity of evidence bytes, not by itself that the test ran; verify result-bundle contents and the actual assertion/outcome. The script must not fill PASS from a supplied status string alone.

Do not grep the entire historical ledger for the word 'unverified' and treat preserved history as a current failure. Parse the current manifest and its explicit links to historical rows. Conversely, do not delete historical failure text to make a text-search gate green. Current authoritative rows must account for every required historical obligation one by one.

## Complete ownership and acceptance mapping

| Obligation family | Implementation/evidence owner and required closure |
| --- | --- |
| E00–E04 foundations, format fidelity, native-window tabs, session restore, editor | Preserve the audited resolved architecture; final current-app open/edit/save/restore, data-safety, selection/lifecycle proof. Do not restore obsolete single-window assumptions. |
| E05 highlighting performance/current-line/themes | E22 supplies real Release/full-path and main-actor measurements and chrome behavior; E23 wires semantic roles, at least eight themes and safe custom themes. This gate verifies actual evidence and unchanged declared budgets. |
| E06–E09 parsing, native Preview, outline, folder browser | Map each still-applicable old manual/Release row to final same-behavior or stronger evidence. Already resolved #34/#36/#37 are not reopened absent a concrete regression. Include links/images/selection and FileTree application integration. |
| E10/E11 editing, multi-format and TeX | Consume E22's final language profiles/TeX recognition and real round trips; TeX source never enters Markdown Preview. Highlighting claims need actual maintained grammar proof or the contract-approved deliberate fallback. Full TeX compilation stays out of scope. |
| E12 static/export/PDF | #118 plus #88: real menu/save-panel export, executed pagination, independently inspected artifacts, parity, bounded assembly, safe resource reads and crash/asset recovery. Preserve PR #114's completed as-built reconciliation and update only genuine later drift. |
| E13 settings | #53/E17 legacy import and state rehearsal; E22 no inert parser fields; E23 theme settings. Live-apply tests on already-open documents for editor/parser/preview/export/format/theme choices, no relaunch or source mutation. |
| E14 contributions/filters/palette | #117 destination/anchor/snapshot contract and E22 command registry. Actual built-in/discovered filter, selection replacement, undo, error, timeout/cancel, close/supersession and multi-window targeting under #88. |
| E15 identity/visual/accessibility | E23 final approved icon/Finder integration; real VoiceOver, keyboard-only, light/dark, Increase Contrast, Reduce Transparency, Reduce Motion and supported text/window sizes across final surfaces. A screenshot's nonblank assertion is not enough. |
| E18 external-file changes | #119/#120/#88: clean/dirty changes, own-save, conflict actions, moves/deletion, native conflict-close, view-state restoration, watcher/probe limits and measured Release performance. |
| E19 math | All six #116 residual areas, including structured errors, accessible equations, delimiter/currency parity, source identity/navigation and live post-#62 re-verification. |
| E20/E21 diagrams | #79/E23: Mermaid/D2/Graphviz neutral/default contrast and print policy, real renderer limits/memory/cancellation, offline containment. D2's internal WASM unsafe-eval remains confined to its trusted local harness; it is not permission for active Quick Look output. |
| E11 HTML Preview races | #121: immutable request/root identity, contained opened-object reads, task-stop and stale navigation behavior, actual hostile WebKit/network fixtures. |
| Final language/product/distribution | #17 final catalog/locale freeze; #18 actual CLI, development-state/legacy/theme migration, clean Gatekeeper install and two consecutive signed-build Sparkle update rehearsal. All exact-candidate required checks belong to V before P. |

In the implementation pass, generate individual IDs under each family, not one green umbrella row. #116's six areas and #118's multiple obligations cannot be collapsed into 'issue closed'. Keep old real performance/UI proofs as historical evidence and name precisely which current behavior and artifact they do or do not establish.

## Supersession and scope discipline

A stale test can be retired only with its old behavior and a named stronger current test/evidence, or an original approved non-goal citation. 'SUPERSEDED' is a relationship between records, not a fourth way to waive a required behavior. The current required behavior still ends FIXED or PROVED. An optional REJECTED_FOR_1_0 row names the original permission and confirms no unsupported runtime/public claim ships.

No new capability, speculative edge-case epic or repeated full historical search is authorized here. A newly observed crash, data-loss/security failure, broken workflow or disproved previous proof is a concrete defect: preserve a reproduction and trace it to the existing owner, adding a focused issue only when it genuinely has no owner. Issue count is not the progress metric; resolved required behaviors and valid evidence are.

## Fresh orthogonal whole-repository review

Freeze an exact S/V source and give each review pass a distinct question. Review source and tests, not only summaries of prior bot findings:

- Data/lifetime correctness: FileCore/Workspace save, recovery, identity transfer, session restore, multiple windows, CLI and update termination; stale completions and cancellation after durable writes.
- Security/resource admission: contained filesystem reads, HTML/CSP, renderer/WebKit workers, Quick Look grants, custom themes, user filters, CLI framing and update-signature/publishing boundaries.
- Behavioral integration: command/menu/palette eligibility, actual FileTree app layer, smaller Preview/JSONSupport paths, Unicode/encoding/line endings, source positions and new E22/E23 interfaces.
- Performance/lifecycle: real Release hot paths, cold starts, long documents, repeated renderer/theme/Quick Look cycles, detached work, queues/descriptors/cache bytes and main-actor stalls.
- Evidence/UX/accessibility: whether tests exercise the claimed route; native alerts/menus/first-run/import/update/VoiceOver; final translation/identity/print claims and unsupported fallback disclosure.

Record reviewer provenance, inspected scope, concrete findings, discriminating reproduction/tests and resolution. Different lenses are not automatically independent reviewers; claim independent review only when separate actual executions/readers are evidenced. Re-review changed areas and their affected contracts after fixes. A global zero-findings message or zero TODO markers is not a proof of correctness.

Prioritize the areas PR #51 read less deeply: FileTree app glue, CLI and smaller Preview/JSONSupport paths, plus all E22/E23/#116–#121 changes. Do not spend the final review repeatedly rediscovering already resolved historical issues while leaving those seams unread.

## Gate validator and final execution

Implement a deterministic offline validator for the manifest/schema/links/digests and artifact identity. It rejects missing/duplicate obligation IDs, unmapped required rows, unknown final states, unsupported rejection, failed/blocked/skipped critical tests, stale source/strings/artifact hashes, unverifiable result references and unresolved release-relevant P0/P1/P2. Cosmetic P3 needs explicit owner acceptance with no functional/security/data-loss impact hidden by reclassification.

A separate read-only live repository check captures current issue/PR dispositions and the exact candidate ref. If repository access is unavailable, report BLOCKED; do not use an old issue snapshot as current release authorization. The validator never closes issues, publishes releases, alters test results or requests a merge itself. Keep immutable validation output with the inputs it evaluated.

At S run affected and full package/app suites, current real Release benchmarks and engineering UI lane. At V run the exact-artifact lane from #88 on the supported interactive Mac: complete critical native UI, external-file/conflict-close, HTML/PDF and independent artifact inspection, math/diagrams, custom themes, Finder/Quick Look, first run/import/update, non-English and VoiceOver. Capture positive controls and failure diagnostics. A rejected automation permission is a blocked run, not a product pass or permission to bypass the assertion.

Run the stateful migration and signed N -> N+1 update rehearsal with #18's preserved fixture manifests. Verify all selected app/extension/CLI binaries come from the candidate, not a similarly named Debug installation. After every fix create/reidentify the candidate, repeat affected proof and the final critical regression suite, and recompute localization/artifact records. Never select only the first successful rerun while hiding failed attempts.

## Implementation sequence and stop conditions

1. Reconcile the S/V/P sequencing wording explicitly without touching E22's work; create the finite per-obligation manifest from existing authoritative rows and current issue criteria.
2. Consume implementation and evidence from each owner, preserve previous completed as-built work and perform only the authorized delta reconciliation.
3. Execute fresh orthogonal review and resolve concrete findings; establish S with all application-side release code/strings present.
4. Complete #17, construct private V artifacts and execute the complete final evidence matrix. Keep #115 open while any required row is unresolved.
5. Validate manifests, actual results, live blockers and exact artifact/strings. Close #115 only when its full final matrix is satisfied. P remains a separately authorized action by the release process, never an automatic side effect of a documentation commit.

Allowed files: current/historical evidence manifests, validation scripts/tests, narrow release-contract sequencing documentation and true as-built corrections. Product fixes stay in their existing owner PRs. Stop on any missing required proof, contradictory authority, unapproved budget relaxation, lost authored data, artifact mismatch, unsupported security guarantee or attempted public publication before P.

## Self-review and completion

Review addressed the localization/candidate loop, old scaffolds mistaken for current status, issue closure mistaken for evidence, ignored prior audit completion, blanket 'superseded' waivers, skipped UI/PDF tests, hashes mistaken for execution proof, correlated reviews described as independent, and newly signed bytes after a completed manual pass.

This is a design for obtaining and validating proof, not proof itself. The only permitted final gate outcomes are GO for the exact verified artifact or NO-GO with the precise remaining obligations. There is no 'ready except for manual testing' release state.
