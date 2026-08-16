> **Title:** [EPIC-15] Liquid Glass polish + accessibility + whole-app feature-complete audit
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** E09, E19, E21 + feature-complete gate

## Owner summary

E15 is the deliberate transition from "all major macOS 1.0 features exist" to "the complete app feels coherent, native, accessible and fast enough to ship." It must not run while major user-facing features, public identity or release-critical evidence are still undefined underneath it.

The feature-complete gate before E15 therefore covers the whole real application and freezes the final public identity. E15 consumes that frozen identity, closes cross-feature release blockers, finalises the first-run/onboarding experience and performs the whole-app visual/accessibility/performance pass. It must not turn unknown evidence into a green checkbox.

## Context

D1 means Liquid Glass is mostly automatic (Xcode 26 SDK, macOS 26), but a deliberate audit separates "runs on Tahoe" from "feels native to Tahoe". The expanded macOS 1.0 scope also means this epic owns the final cross-feature accessibility/performance/coherence pass after E19-E21.

`planning/RELEASE_HARDENING.md` is binding for the feature-complete and E15 gates.

## Required feature-complete inputs

Before broad E15 polish begins, the feature-complete gate must have:

- frozen final public product name, bundle/update identity strategy, CLI public name where affected, repository/public-link strategy and migration strategy from development identifiers;
- one owner-readable release-evidence ledger covering every macOS 1.0 capability/epic;
- explicit status for earlier evidence debt rather than assuming a closed epic is release-proven;
- a plan/environment for actually executing critical XCUITests on macOS 26;
- the text round-trip fidelity corpus from `planning/RELEASE_HARDENING.md`;
- no unresolved P0/P1 integration defect; P2 acceptance must be explicit and owner-readable.

## Scope

- Consume and maintain the feature-complete release-evidence ledger while release-blocking integration findings are closed.
- Execute/coordinate the complete-product dogfood matrix across document lifecycle, editing, formats, folders, preview, export, settings, math, diagrams and contribution/text-filter behaviour.
- Ensure critical UI tests have real execution evidence rather than build-for-testing-only evidence; local-Mac evidence is valid when hosted CI cannot run them, but must be recorded repeatably.
- Verify text round-trip fidelity including encodings, BOM where relevant, LF/CRLF, Unicode/emoji/CJK, final-newline state, large files, no-op save, Save As and external atomic rewrites.
- Toolbar: verify native Liquid Glass treatment; no custom backgrounds behind system bars without documented reason.
- Sidebar/inspector: confirm material correctness, scroll-edge effects and native behaviour.
- Custom glass elements use the minimum needed effect; no glass-on-glass stacking.
- Math and diagram preview/error/focused-preview states receive the same coherent light/dark, contrast, motion and accessibility treatment as ordinary Markdown.
- Final app icon/marketing app assets are created using the **already frozen** public identity.
- Finalise the welcome/first-run/sample-document UI and all in-app onboarding copy before E16 string freeze. E17 packages/verifies this flow; it does not invent a new first-run UI later.
- Accessibility: Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver over tabs/tree/outline/derived technical content; Dynamic Type/appropriate text sizing where sensible.
- Performance re-audit against roadmap budgets plus feature-specific E19-E21 budgets; memory audit with representative mixed Markdown/math/diagram documents and 20 tabs.

## Deliverables

1. Feature-complete/release-evidence ledger with release-blocking findings resolved or explicitly classified.
2. Recorded critical XCUITest execution evidence on a suitable macOS 26 environment.
3. Text-fidelity corpus results and deliberate-normalisation record (if any).
4. Glass/coherence audit checklist + fixes.
5. Final icon/app marketing asset set using the frozen identity.
6. Final first-run/sample/onboarding UI and copy handed to E16 for localisation.
7. Accessibility test pass (manual + automated smoke where practical).
8. Whole-app performance/memory audit report vs. approved budgets.
9. Manual dogfood matrix covering normal, error/recovery and destructive/document-safety paths.

## Acceptance criteria

- [ ] Final public identity required for app UI/assets is frozen before E15 sign-off.
- [ ] No major macOS 1.0 feature epic remains unfinished or architecturally provisional.
- [ ] The release-evidence ledger contains no unresolved P0/P1 and no capability is marked passed solely because its issue is closed.
- [ ] Critical XCUITests have actually executed on macOS 26; unavailable rows are marked unverified rather than inferred.
- [ ] Text round-trip fidelity corpus has no unexplained/gratuitous file normalisation.
- [ ] Zero unjustified custom backgrounds behind system bars.
- [ ] App looks correct in light/dark, transparency on/off, contrast on/off.
- [ ] Math and diagram states are visually coherent and accessible alongside normal Markdown content.
- [ ] Approved whole-app performance budgets remain green with representative mixed technical documents.
- [ ] Critical document-safety, recovery, Save As, external-edit and session journeys still pass after all feature integration.
- [ ] First-run/sample/onboarding UI and in-app copy are final enough to freeze/localise in E16.
- [ ] Icon exports correctly at all required sizes from the frozen product identity.

## Out of scope

- New major product features.
- Deciding the public brand after E15 starts; identity is a feature-complete-gate input.
- Marketing website and release notes (E17).
- iPad implementation; that begins only after the macOS 1.0 release.

## Architecture gate

E15 must satisfy `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. It is evidence-backed whole-product work, not a late opportunity to redesign feature architecture casually.
