> **Title:** [EPIC-15] Liquid Glass polish + accessibility pass
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** E07, E09

## Context

D1 means glass is mostly automatic (Xcode 26 SDK, macOS 26), but a deliberate
audit separates "runs on Tahoe" from "feels native to Tahoe".

## Scope

- Toolbar: stock items verify glass treatment; custom items adopt
  `.buttonStyle(.glass)`/`.glassProminent` as appropriate; `ToolbarSpacer`
  grouping; no custom backgrounds anywhere behind bars
- Sidebar/inspector: confirm material correctness, scroll-edge effects,
  `.backgroundExtensionEffect()` where content passes under the sidebar
- Custom glass elements (tab bar, status overlays) grouped in
  `GlassEffectContainer`; no glass-on-glass stacking; tint sparingly per HIG
- App icon rebuilt in Icon Composer (Liquid Glass layered icon)
- Accessibility: Reduce Transparency, Increase Contrast, Reduce Motion,
  VoiceOver over tabs/tree/outline; Dynamic Type where sensible
- Performance re-audit against §8 budgets; memory audit with 20 tabs

## Deliverables

1. Glass audit checklist executed + fixes
2. New icon set + marketing assets
3. Accessibility test pass (manual + XCUITest VoiceOver smoke)
4. Perf/memory audit report vs. budgets

## Acceptance criteria

- [ ] Zero custom backgrounds behind system bars (audit list empty)
- [ ] App looks correct in light/dark, transparency on/off, contrast on/off
- [ ] All §8 performance budgets still green in CI
- [ ] Icon exports correctly at all sizes from Icon Composer

## Out of scope

Marketing website; screenshots for release (E17).

## Notes

Reference: WWDC25 sessions 219/310/323 + "Adopting Liquid Glass" tech overview.
