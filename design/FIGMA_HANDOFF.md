# MostlyText identity: Figma handoff

**Owner summary.** The MostlyText mark (Slant) and its lockup rules are
settled at release-candidate stage. The Figma session's job is production:
outline the wordmark and build the lockup artwork from the canonical files
below. It is **not** to explore, redraw or reinterpret the mark. Everything
needed is on this page. You don't need the exploration history
(`design/brand/gen2/`, `gen3/`, the old boards); ignore it.

## Canonical assets (import these, nothing else)

| File (in `design/brand/slant/validation/`) | Use |
|---|---|
| `slant-master.svg` | The mark above 40 px, and all general artwork. 100-unit box. |
| `slant-32.svg` | The mark at 18–40 px. Drawn on a 32 px grid. |
| `slant-16.svg` | **Microglyph** for ≤17 px only. |
| `slant-icon-16-inner.svg` | **Microglyph** for inside the 16 px app icon only. |

Provenance, licences and rebuild commands: `design/brand/PROVENANCE.md`.

## Effective decisions (the current state of D-010 to D-021)

- **Mark:** Slant is an M and T sharing one stem, leaning 12° forward, with a
  wedge cut at the end of the crossbar. Stems 17, diagonals 15 (on the
  100-unit master). (D-010, D-011)
- **Canonical lockup:** the mark plus a leaned Inter Tight Bold wordmark in
  **one colour**. It must read fully in monochrome. A two-tone "Text" is a
  secondary promotional treatment only, never canonical. (D-012, D-013)
- **Size artwork:** use the table above. Horizontals of the small artwork sit on
  whole pixels, so don't rescale or resample it. (D-014)
- **Microglyphs:** `slant-16.svg` and `slant-icon-16-inner.svg` are deliberate
  simplifications in which the wedge and shared stem recede. **Never enlarge
  them, never use them as general artwork, and never derive other artwork from
  them.** (D-020)
- **Usage rule:** never pair the mark with parallel stripes or a red-and-blue
  scheme. (D-016)
- **Status:** geometry is **release-candidate frozen**. Optical corrections from
  the human read test or the macOS icon render are allowed, but each must be
  recorded as a new decision (D-023 onwards), never made silently. (D-018)
- **Human read test and similarity:** see "Release gates" below. The
  similarity work is a visual screen, not a legal assessment. If the test
  shows automotive associations, compare 8°, 10° and 12°; no fallback angle is
  set in advance. (D-019, D-021)

## Lockup metrics (D-015)

Let **F** be the wordmark's font size.

| Property | Value |
|---|---|
| Typeface | Inter Tight **Bold Italic** (700). Its own italic angle is about 9.5°. |
| Extra lean | Shear the outlined wordmark a further **2.6°** (2.63°) so the total is **12°**, matching the mark. Don't shear upright Bold by 12°. |
| Tracking | −2.5% (−0.025 em) |
| Cap height | 0.7367 F (measured) |
| Mark size | The mark's letters are **1.15 × cap height = 0.847 F** tall |
| Vertical position | The bottom of the mark's letters sits **on the wordmark baseline** |
| Gap | **0.2 F** from the mark's lower-right stem to the wordmark's M, measured along the 12° lean |
| Weight relation | The mark's stems are about 1.4× the wordmark's stems. The mark leads, so don't use weight 800 for the wordmark. |
| Clear space | At least the height of the mark's crossbar on every side |
| Minimum size | Wordmark at 12 px on screen (5 mm cap height in print). Below that, use the mark alone. |

**Wordmark outlining tasks (Figma):**
1. Set "MostlyText" in Inter Tight Bold Italic 700 at −2.5% tracking.
2. Outline it and apply a 2.63° horizontal shear.
3. Correct the o, e and y curves where the extra shear distorts them.
4. Tighten the "yT" pair, which opens up when slanted.
5. Assemble the light and dark one-colour lockups with the metrics above.

Record the Inter Tight version used.

## Colour (working values, not frozen)

Lockup: single ink, e.g. `#11141A` on light and `#F3F5F9` on dark.
Icon, two-tone T only: light M `#14171D` / T `#2F5FE6`; dark M `#F3F5F9` /
T `#7EA4FF`. The macOS icon build may change these.

## Release gates still open (public identity isn't frozen until all four close)

| Gate | Owner / where | Status |
|---|---|---|
| 1. Wordmark outlined with curve and "yT" corrections | **Figma** (this handoff) | Open |
| 2. macOS icon set (light, dark, clear, tinted) built in Icon Composer and checked in a real Dock and Finder | **Mac** | Open |
| 3. Blind human read test passes D-019 | **Humans**, using `design/validation/read-test/` | Open |
| 4. Trademark register search (WIPO, USPTO, IPOS) run and reviewed | **Human searcher / reviewer**, using `design/brand/TRADEMARK_SEARCH.md` | Open. No legal conclusion has been drawn |

## Record-keeping

Add new decisions to `design/DECISIONS.md` as D-023 onwards. Don't edit
earlier rows: supersede them.
