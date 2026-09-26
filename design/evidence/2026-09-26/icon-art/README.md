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
  is the same renderer the OS uses.
- **Not covered:** a live app icon in the real Dock and Finder. Wiring the
  `.icon` file into `MacDown2/MacDown2/Assets.xcassets/AppIcon.icon` and
  building via `xcodebuild` produced an app with **no icon at all** (see
  "Toolchain finding" below) rather than the new mark — that path needs a
  fix before Dock/Finder screenshots are meaningful. The 16 px exports above
  are the practical substitute: same renderer, true pixel size, all system
  appearances, just not inside a running `.app` bundle. The full UI screenshot
  set from `DESIGN_CONTEXT.md`'s capture protocol (editor, preview, settings,
  etc.) was not attempted, since it depends on a working Release build with
  the real icon and normal app launch, which the same toolchain issue
  blocks confidently attributing to icon changes alone.

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

## Toolchain finding: `.icon` catalog members don't compile via `xcodebuild`/`actool` on this machine

Copying the Icon Composer `.icon` bundle into
`MacDown2/MacDown2/Assets.xcassets/AppIcon.icon` (replacing
`AppIcon.appiconset`) and building with `xcodebuild -configuration Release
build` (Xcode 26.6, build 17F113) produces an app with **no
`Assets.car`, no icon at all** in `Contents/Resources`. A minimal direct
repro confirms it:

```
actool Assets.xcassets --compile <out> --app-icon AppIcon --output-partial-info-plist <out>/partial.plist ...
```

exits 0 with no errors or warnings about the icon itself, but writes nothing
but an empty `partial.plist` — the `.icon` bundle's `icon.json` (a valid
Icon-Composer-exported document; layers, fill and `supported-platforms` all
present) is silently not recognised as icon content by this system's
command-line `actool`. This looks like a genuine version gap between Icon
Composer's `.icon` export format and this machine's bundled `actool`, not a
project configuration error (`ASSETCATALOG_COMPILER_APPICON_NAME` is
correctly set to `AppIcon`, and the classic `.appiconset` compiles and links
into a working `.icns` normally). This needs a person with Xcode.app's own
GUI build (which may invoke a newer/different icon-compilation path) or an
updated Xcode/actool to resolve, before the real Dock/Finder/full-UI-screenshot
checks in `DESIGN_CONTEXT.md` can be completed. **The implementation-side
files this required (`Assets.xcassets/AppIcon.icon`, the removed
`AppIcon.appiconset`, the regenerated `.xcodeproj`) were reverted after
testing** — the design lane stays read-only toward implementation code; only
this evidence and the `.icon` source file are new.

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
