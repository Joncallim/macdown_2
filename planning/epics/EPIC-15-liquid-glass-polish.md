> **Title:** [EPIC-15] Liquid Glass polish + accessibility + whole-app feature-complete audit
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** E09, E19, E21 + feature-complete gate

## Owner summary

E15 is the deliberate transition from "all major macOS 1.0 features exist" to "the complete app feels coherent, native, accessible and fast enough to ship." It must not run while major user-facing features are still arriving underneath it.

The feature-complete gate before E15 therefore covers the whole real application: document lifecycle, editing, formats, folders, preview, math, diagrams, export, settings and extension infrastructure. Any release-blocking integration failure found at that gate is fixed before cosmetic polish continues.

## Context

D1 means Liquid Glass is mostly automatic (Xcode 26 SDK, macOS 26), but a deliberate audit separates "runs on Tahoe" from "feels native to Tahoe". The expanded macOS 1.0 scope also means this epic owns the final cross-feature accessibility/performance/coherence pass after E19-E21.

## Scope

- Execute the feature-complete gate across all major macOS 1.0 capabilities before visual polish is signed off.
- Toolbar: stock items verify glass treatment; custom items adopt `.buttonStyle(.glass)`/`.glassProminent` as appropriate; `ToolbarSpacer` grouping; no custom backgrounds anywhere behind bars.
- Sidebar/inspector: confirm material correctness, scroll-edge effects, `.backgroundExtensionEffect()` where content passes under the sidebar.
- Custom glass elements (status overlays) grouped in `GlassEffectContainer`; no glass-on-glass stacking; tint sparingly per HIG. *Amended at #28: there is no custom tab bar — tabs are native `NSWindow` tabs (as-built E03) and get glass from AppKit; verify, don't rebuild.*
- Math and diagram preview states receive the same coherent light/dark, contrast, motion and accessibility treatment as ordinary Markdown.
- App icon rebuilt in Icon Composer (Liquid Glass layered icon).
- Accessibility: Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver over tabs/tree/outline/derived technical content; Dynamic Type where sensible.
- Performance re-audit against §8 budgets plus feature-specific E19-E21 budgets; memory audit with representative mixed Markdown/math/diagram documents and 20 tabs.
- Whole-app manual dogfood matrix covering normal, error/recovery and destructive/document-safety paths.

## Deliverables

1. Feature-complete gate record with release-blocking findings resolved or explicitly deferred with justification.
2. Glass audit checklist executed + fixes.
3. New icon set + marketing assets.
4. Accessibility test pass (manual + XCUITest VoiceOver smoke where practical).
5. Whole-app performance/memory audit report vs. approved budgets.
6. Manual dogfood matrix for representative complete-product workflows.

## Acceptance criteria

- [ ] No major macOS 1.0 feature epic remains unfinished or architecturally provisional.
- [ ] The feature-complete gate has no unresolved release-blocking integration defect.
- [ ] Zero custom backgrounds behind system bars unless a documented exception is required by the platform.
- [ ] App looks correct in light/dark, transparency on/off, contrast on/off.
- [ ] Math and diagram states are visually coherent and accessible alongside normal Markdown content.
- [ ] Approved whole-app performance budgets remain green with representative mixed technical documents.
- [ ] Critical document-safety and recovery journeys still pass after all feature integration.
- [ ] Icon exports correctly at all sizes from Icon Composer.

## Out of scope

- New major product features.
- Marketing website and release screenshots (E17).
- iPad implementation; that begins only after the macOS 1.0 release.

## Notes

Reference: WWDC25 sessions 219/310/323 + "Adopting Liquid Glass" tech overview. E15 must follow `planning/EPIC_STANDARD.md`; polish is evidence-backed whole-product work, not a late opportunity to redesign feature architecture casually.
