# Diagram colors for screen and paper (#79)

## Owner summary

Default Mermaid, D2 and Graphviz artwork follows the preview's text and
background colors on screen. A dark preview therefore gets light diagram
labels, outlines and edges on its dark canvas. PDF and print keep a separate
light, readable palette. Explicitly authored colors remain content, even when
an author chooses low contrast. There is no image inversion or general search
and replacement of black paint.

This owner-approved policy replaces the earlier fixed-light screen policy on
2026-10-27. It adds no theme editor, renderer, network service, dependency or
export pipeline. Native preview and PDF calibration remain required before
claiming issue #79 is complete.

## Reconciliation baseline

The screen-context change starts from reviewed commit
`82c07dd42f71c3269e5f1a45d1f0f6a28bf7df1e`, whose integration base is
`6b27391793cc02f2a101f1b213382b32a907bfd7`. No unrelated #113 work or legacy
porting source is changed. Existing WebKit isolation, structured arguments,
worker retirement, cancellation, SVG occurrence namespaces and memory limits
are retained.

## Implementation boundaries

- `Themes.DiagramPalette` owns the one shared default policy. Foreground and
  canvas are separate variables. `preview-context-v1` resolves them from the
  same `theme.chrome` colors used by `PreviewTheme`. The resulting default
  text/stroke is the preview foreground; default node fill is its background.
  `neutral-light-v1` remains the PDF/print policy.
- Values are normalized to finite, bounded, opaque sRGB hex colors. Invalid
  input colors fall back to the print-safe color for that role. Explicit
  author colors are passed through each engine rather than normalized here.
- All three render-context adapters carry destination and resolved palette.
  Cache identity includes both, source digest, renderer version, layout and
  output kind. Mermaid also identifies raster scale and admission limits.
  Native preview tasks use source plus context fingerprint, so theme changes
  start a new request; cancelled old requests cannot publish their result.
- Mermaid receives base-theme variables as defaults. Its own directive parser
  applies explicit `themeVariables` from init directives and frontmatter;
  the resolved authored background also supplies the SVG/PNG backing canvas.
  Security, secure-key configuration, theme selection and theme CSS remain
  protected. `securityLevel` remains strict, including when source requests
  loose security. Class/style directives continue to retain authored paint.
- D2 uses the bundled `themeOverrides` and `darkThemeOverrides` APIs for screen
  defaults. Explicit literal paints, per-token source overrides and selected
  non-default source themes remain authored. Print retains the bundled light
  profile. Generated theme-token paints receive literal SVG fallbacks because
  AppKit does not reliably apply the scoped classes; existing literal paint
  attributes are untouched. This extends the existing generated-background
  repair without recoloring authored artwork.
- Graphviz receives native graph/node/edge defaults. Source attributes override
  them, including explicit black text and strokes. Screen fills for nodes and
  clusters follow the canvas; print keeps its native shape-fill defaults.
  Authors who want a specific fill should set `fillcolor` explicitly: a screen
  default `fillcolor` takes precedence over Graphviz's implicit fallback from
  `color` to fill, as any DOT default attribute does.
- Each returned SVG has its own default backing canvas. Authored backgrounds
  remain above that canvas. Mermaid rasterizes that same final SVG; export
  retains the vector artwork.
- Mermaid's 2x raster remains bounded to 4,096 pixels per side and 8,388,608
  pixels total before allocation. Cache accounting includes retained SVG and
  PNG bytes. No resource budget is increased.

## Focused verification

Run the source-only checks serially from the repository root:

```sh
cd MacDown2/Packages/MacDownKit
swift test --force-resolved-versions --filter 'DiagramPaletteTests|MermaidDiagramCacheTests|MermaidDiagramCacheAccountingTests|D2DiagramCacheTests|GraphvizDiagramCacheTests'
```

From the repository root, `node MacDown2/scripts/test-diagram-palette.cjs` uses
the bundled Mermaid parser and bundled D2/Graphviz WebAssembly (WASM) binaries.
It checks screen/light/print defaults, authored colors and strict Mermaid
security without launching WebKit or the app. D2's native-fallback helper is
also checked for generated-token resolution and literal authored-paint
retention. The script substitutes only DOM canvas composition and Mermaid's
layout/raster step; it is not visual/native evidence.

The final Swift source-only run passed 25 tests across five suites. All changed
package renderer tests also compiled. Changed Swift files passed strict lint and
format validation. The first Node fixture run failed because its D2 assertion expected
CSS syntax for a literal SVG paint. Diagnostic runs then found an unquoted DOT
keyword in a fixture and Graphviz's omission of default black text attributes.
These assertions/fixtures were corrected against actual bundled output; their
failed logs are retained in `/tmp/issue79-screen-harness-tests*.log`. Final
revision results are recorded in the commit handoff. No failure was dismissed
as a pre-existing flake.

## Verification still required

The Swift WebKit tests now cover authored Mermaid init/frontmatter colors,
light/dark/light worker reuse, D2 default text/edges and literal SVG fallbacks,
Graphviz default edges/labels, explicit black paints and screen canvases. They
are compiled by the focused Swift command but are not executed in this slice.
The app adapter test checks that all three engines share screen resolution
and retain print-safe output; app tests are also not executed here.

Before completion, run the affected real-WebKit suites, full locked package
suite, strict lint/format checks and pinned Release app build serially. Exercise
native preview in light/dark/high-contrast themes and compare HTML/PDF output
on the same artifact. Include default diagrams, long/edge labels, clusters,
authored fills/strokes/backgrounds and config colors, transparent backgrounds,
negative SVG origins, twelve-slice pies and D2 native decoding. No native,
Release, printed PDF or issue-closure proof is claimed by this source slice.
