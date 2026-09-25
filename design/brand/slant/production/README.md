# Slant production geometry

**Owner summary.** This folder turns the frozen Slant sources into production
outlines. It contains the flattened mark (the four validation SVGs with strokes
expanded, clips applied and the skew baked in) and the outlined MostlyText
wordmark and lockup. The same geometry was placed in the canonical Figma file,
[MostlyText — Brand Identity (Slant 12°)](https://www.figma.com/design/x5wTgOFnR9GgNFfUqWwKmX).
No mark geometry was changed. The wordmark gained three measured optical
corrections, listed below. Nothing here needs a Mac. The macOS icon pipeline,
the human read test and the register search are still open (D-017, D-018).

## Files

| File | What it is |
|---|---|
| `mark.mjs` | Rebuilds each source SVG (`../validation/slant-*.svg`) as one filled outline: the stroked V with a mitre join, the stem, the T, and the clip, then the transforms |
| `glyphs.mjs`, `wordmark.mjs` | Shapes “MostlyText” with HarfBuzz (the font's own kerning), applies stroke compensation, the 2.6° slant, −2.5% tracking and the pair corrections |
| `build-geometry.mjs` | Writes `geometry.json`: the mark outlines (plus separate M and T parts for two-tone and icon layers), the wordmark and the lockup placement |
| `export-svgs.mjs` | Writes `out/`: `mostlytext-wordmark.svg`, `mostlytext-lockup.svg` and `slant-*-outline.svg` |
| `verify-outlines.mjs` | Renders each source SVG and its outline in Chromium and prints the pixel differences |

## Rebuild

```sh
cd design/brand/slant/production
npm install
# Inter Tight Bold Italic (SIL OFL), not committed:
curl -sL -o InterTight-BoldItalic.ttf \
  https://fonts.gstatic.com/s/intertight/v9/NGShv5HMAFg6IuGlBNMjxLsC66ZMtb8hyW62x0ylGC5X.ttf
# expected sha256 f6908b1a008b5f86c502390161e91f8e1c7960342bdae61aaa229130b745c49b
npm run build && npm run verify   # verify needs Chromium (CHROMIUM_PATH)
```

## Verification

- **Mark outlines against the source SVGs:** no solid-pixel differences at 16–2048 px.
  The only residuals are anti-aliasing on horizontal edges that land on
  half-pixel rows: at most 64/255 on single edge pixels, with a mean of
  0.03/255 or less at 1024 px.
- **Wordmark:** measured with perpendicular stroke-thickness sampling and
  facing-profile pair spacing, as below.

## Wordmark optical corrections (D-025)

1. **Slant stroke compensation.** The extra 2.6° shear thickens edges that run
   up-left and thins edges that run up-right, by about 2.2% at 45°. Before the
   shear, each outline edge is offset along its normal by the exact inverse of
   that change, using a nominal 300-unit stroke. The imbalance on the o's
   diagonals falls from ±2.2% to 0.5% or less. Horizontal edges, heights and
   overshoots are unchanged.
2. **yT −60 units (1/2048 em).** The y's arm runs at about 60° and the T stem at
   12°, so a wedge-shaped hole opens under the crossbar. After the fix, the y
   terminal sits 122 units under the crossbar, with the vertical clearance kept
   at 112 units. The y/T counter excess over T/e falls by a third. Tucking
   deeper blurs the gap under the bar at small sizes.
3. **xt +60 units.** The −2.5% tracking made the x's top touch the t's crossbar
   (−18 units). It now clears by 42 units, matching ly (41 units), the tightest
   intended pair.
