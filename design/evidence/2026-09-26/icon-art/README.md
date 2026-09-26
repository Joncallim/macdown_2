# Production icon validation, 2026-09-26

**Owner summary.** This is the Mac-side production validation gate from
`DESIGN_CONTEXT.md`/D-017 item 2: comparing the 8°/10°/12° leans and the
current-vs-derive-from-master small-size drawings directly in Icon Composer,
then checking real rendering at true small size. This is a direct-comparison,
owner/design judgment call (D-026), not a statistical human-test gate.

## What this covers, and what it doesn't

- **Covered:** the 8°/10°/12° lean comparison in Icon Composer; the
  current-vs-derived 16 px/32 px small-size comparison in Icon Composer; a true
  16×16 px render of the chosen lean in all six system appearances (Default,
  Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark), exported through
  Icon Composer's own production rendering pipeline (`File > Export…`), which
  is the same renderer the OS uses; **a live app icon built through the
  normal `xcodebuild` pipeline and checked in the real Dock, Finder icon view
  and Finder list view** (see `design/evidence/2026-09-26/dock-finder/`) —
  Gate 2 (D-017 item 2) is now closed on that basis.
- **Not covered:** the full UI screenshot set from `DESIGN_CONTEXT.md`'s
  capture protocol (editor, preview, settings, etc.) — out of scope for this
  pass, since it wasn't blocked by anything specific to the icon work and
  would need a separate session. Also not covered: cascading the 10° lean
  into the production wordmark/lockup/Figma files (see D-027).

## 1. Lean comparison (8° / 10° / 12°)

Source: `lean-8-1024.png`, `lean-10-1024.png` (also `MostlyText-lean10.icon`,
the saved Icon Composer document used for every export below), `lean-12-1024.png`
— all rendered from `design/validation/round-2/candidates.mjs`'s `slantAt()`,
the same parametric construction as the frozen mark (wedge cut, diagonals 15,
stems 17), only the angle changed.

Reviewed side by side in Icon Composer at 1024 pt and at the small platform
preview size, in Default, Dark and Mono/Tinted appearances.

- **12°** (the current frozen geometry, D-011): the most energetic, but the
  diagonal rake reads the most like a speed stripe — this is the exact
  perceptual risk D-021 recorded (round-1: 6/8 motorsport/performance
  associations, 4/8 narrowly cars/motorsport).
- **8°**: noticeably calmer and more upright; clearly loses the "forward
  motion" the owner chose Slant for in the first place (D-010's rationale).
- **10°**: the middle ground. Visibly less aggressive than 12° — the
  diagonal read is softer — while keeping real forward lean and most of the
  mark's energy. This is the smallest step back from 12° that meaningfully
  changes the silhouette's rake.

**Decision: adopt 10° for production**, recorded as D-027 in `DECISIONS.md`.
This is a bounded correction under D-021's own instruction ("keep as much
lean as passes"): it changes only the lean angle, not the construction,
wedge cut, or any other frozen parameter.

## 2. Current vs. derive-from-master small-size drawings

Source: `current-16-1024.png` / `current-32-1024.png` (the checked-in
`slant-16.svg` / `slant-32.svg`, hand-lightened per D-014) vs.
`derived-16-1024.png` / `derived-32-1024.png` (the round-2 `R2-16`/`R2-32`
candidates, mechanically derived from the master per the correction principle
approved 2026-09-26, `design/validation/round-2/DIAGNOSIS.md` §4).

Compared in Icon Composer's small platform-preview thumbnails (~30 px). The
derived candidates are visibly bolder and closer to the master's fused,
solid-mass silhouette; the current microglyphs are thinner-legged with a more
open V, consistent with `DIAGNOSIS.md`'s pixel-match findings (current 16 px:
0.866 vs. derived 16 px: 0.943; current 32 px: 0.786 vs. derived 32 px:
0.937). **This direct visual check corroborates the diagnosis. The
derive-from-master correction is accepted** for `slant-16.svg`,
`slant-icon-16-inner.svg` and `slant-32.svg` — recorded as part of D-027.

## 3. True 16×16 px render of the chosen lean, all appearances

`16px-true-size/` holds the six PNGs Icon Composer exported directly at 16 pt
1x (its real production renderer, not a canvas rasterisation test harness) for
the 10° lean, master geometry (not a separate microglyph — see the finding
below). `16px-upscaled-for-review/` holds the same six files upscaled 12×
with nearest-neighbour scaling, for a human to read without zooming their own
screen.

**Finding:** rendered through Icon Composer's actual pipeline, the **master
geometry alone** (no separate hand-tuned microglyph) reads clearly as "MT" at
true 16 px, in all six appearances — Default, Dark, Clear Light, Clear Dark,
Tinted Light, Tinted Dark. This is a materially better result than
`DIAGNOSIS.md`'s canvas-rasterisation test predicted for a naively scaled
master ("Scaled master loses the V and blurs at 16 px", D-014's original
rationale) — Icon Composer's renderer applies its own anti-aliasing and
Liquid Glass shading that the design lane's raw-canvas pixel-match diagnostic
didn't model. **Practical conclusion:** for the macOS **app icon**
specifically, the production pipeline does not need a separate 16 px
microglyph; the master is sufficient. The derive-from-master correction in
§2 above still stands and should still be applied to `slant-16.svg` /
`slant-32.svg` / `slant-icon-16-inner.svg` for the **other** contexts that
render those files directly outside Icon Composer (favicon, in-app chrome at
small size), where no such renderer-side rescue is available.

## Corrected finding: the first attempt used the wrong integration path, not a broken toolchain

The first pass put the `.icon` file **inside** `Assets.xcassets`
(`Assets.xcassets/AppIcon.icon`, replacing `AppIcon.appiconset`) and built
with plain `xcodebuild`. That produced an app with no `Assets.car` and no
icon at all, and a minimal `actool Assets.xcassets --compile …` repro showed
`actool` silently writing nothing for the catalog. The evidence record
initially diagnosed this as an `actool`/toolchain version gap. **That
diagnosis was wrong.** Apple's current Icon Composer documentation (and the
WWDC26 Icon Composer session) says a `.icon` file is added as a normal
top-level project resource **adjacent to** `Assets.xcassets`, not nested
inside it. Nesting it inside the catalog folder meant `actool` treated the
whole `Assets.xcassets` as one opaque `folder.assetcatalog` unit, didn't
recognise the unfamiliar `.icon` child inside it, and silently produced an
empty catalog — an integration-path error, not an `actool` defect.

**Corrected path, verified working:**

1. Place the file at `MacDown2/MacDown2/AppIcon.icon` — a sibling of
   `Assets.xcassets`, not inside it.
2. Remove/rename the old `Assets.xcassets/AppIcon.appiconset` so there's only
   one app-icon source (kept both temporarily is untested and not
   recommended).
3. Regenerate the Xcode project. **XcodeGen 2.46.0 already has native
   support for this** — no manual `.pbxproj` surgery was needed. It adds the
   file with `lastKnownFileType = wrapper.icon`, includes it in the target's
   Resources build phase, and the existing
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` build setting (already in
   `project.yml`) picks it up unchanged, matching the file's basename minus
   extension.
4. A normal `xcodebuild -configuration Release build` (no Xcode.app GUI
   needed) then compiles it correctly: `Contents/Resources/Assets.car` and
   `AppIcon.icns` are both produced, and `assetutil -I Assets.car` shows
   `NSAppearanceNameAqua`/`NSAppearanceNameDarkAqua`/`NSAppearanceNameSystem`/`ISAppearanceTintable`
   renditions (10 tintable renditions were generated for this icon).

**Live verification:** built and launched the real `.app`, then checked it
in `design/evidence/2026-09-26/dock-finder/`:

- `dock-light.png` — the real Dock, running app, light appearance.
- `finder-icon-view-light.png` — Finder icon (grid) view.
- `finder-list-view-light.png` — Finder list view at the true 16 px row-icon
  size.

All three read clearly as the Slant "MT" mark. **Gate 2 (D-017 item 2,
"macOS icon set in Icon Composer and checked in Dock and Finder") is now
closed.** Dark-appearance Dock/Finder screenshots and the full
`DESIGN_CONTEXT.md` UI screenshot set were not captured in this pass (not
blocked by anything specific to the icon work; left for a follow-up
session). **The implementation-side files this required
(`MacDown2/MacDown2/AppIcon.icon`, the removed `AppIcon.appiconset`, the
regenerated `.xcodeproj`) were reverted after testing** — the design lane
stays read-only toward implementation code; only this evidence and the
`.icon` source file under `design/` are new. The correct integration steps
above (steps 1–4) are recorded here for whoever next needs to wire the real
icon into the app permanently — that's an implementation-lane change, not
a design-lane one.

## Files

- `lean-8-1024.png`, `lean-10-1024.png`, `lean-12-1024.png` — the three lean
  candidates at 1024 px, black ink, transparent background.
- `current-16-1024.png`, `current-32-1024.png`, `derived-16-1024.png`,
  `derived-32-1024.png` — the small-size comparison set, upscaled to 1024 px
  for Icon Composer import (source geometry unchanged; only the raster size
  differs from the true 16/32 px it represents).
- `slant-master-2048.png` — the production master outline, 2048 px, for
  reference.
- `MostlyText-lean10.icon` — the saved Icon Composer document: one glyph
  layer (`lean-10-1024.png`) on the default automatic blue gradient fill, no
  background redesign attempted (out of scope for this gate).
- `16px-true-size/`, `16px-upscaled-for-review/` — the six-appearance 16 px
  export set described in §3.

## Rebuild

Regenerate the lean/small-size PNGs from source:

```sh
cd design/validation/round-2
qlmanage -t -s 1024 -o ../../evidence/YYYY-MM-DD/icon-art stimuli/lean-8.svg stimuli/lean-10.svg stimuli/lean-12.svg stimuli/glyph-R2-16.svg stimuli/glyph-R2-32.svg
qlmanage -t -s 1024 -o ../../evidence/YYYY-MM-DD/icon-art ../../brand/slant/validation/slant-16.svg ../../brand/slant/validation/slant-32.svg
```

(`qlmanage -t` renders SVG through QuickLook and preserves alpha
transparency — confirmed empirically; `sips -g hasAlpha` reports `yes` and
composited black-on-transparent renders correctly as Icon Composer glyph
layers.) The 16 px appearance exports are re-created from
`MostlyText-lean10.icon` via Icon Composer's `File > Export…`, Size 16pt 1x,
Appearance "All".
