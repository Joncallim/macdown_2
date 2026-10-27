# Shared neutral diagram palette (#79)

## Owner summary

Mermaid, D2 and Graphviz artwork uses a fixed, opaque light canvas in preview
and export, so changing the editor theme cannot make default diagram text
unreadable. Explicit diagram colors remain authored content. A versioned
palette in `Themes` supplies the shared policy; D2 retains its bundled light
profile and Graphviz retains its native shape-fill defaults.

This is a bounded correction to the existing local rendering path. It adds no
renderer, network service, theme setting, dependency version, pool design or
PDF export pipeline. Native preview and PDF calibration remain required before
claiming issue #79 is complete.

## Reconciliation baseline

The implementation starts from `6b27391793cc02f2a101f1b213382b32a907bfd7`.
It selectively carries the palette and memory-budget intent of `a289643e` and
`14fb4a7c`; their earlier ancestor chain is not an integration prerequisite.
The baseline's typed WebKit results, pool retirement and navigation/cancellation
fixes are retained. Its D2 generated `fill-N7` background repair is retained:
only the bundled white background is made literal for AppKit decoding, while
other authored paint stays untouched.

## Implementation boundaries

- `Themes.DiagramPalette.neutralLight` is the immutable `neutral-light-v1`
  policy. Serialization accepts only that supported palette; the fingerprint
  includes every color and the categorical pie sequence.
- The three render contexts resolve to that palette, including compatibility
  initializers for earlier component-color callers. App appearance is not a
  cache input.
- Cache identities include a source digest, palette fingerprint, bundled
  renderer version, layout policy and output kind. Mermaid also identifies its
  raster scale and raster admission policy.
- Renderer arguments cross WebKit as structured values. The inserted white
  rectangle is behind the renderer's SVG artwork, preserving explicit paint.
- Mermaid rejects missing, non-finite and invalid SVG dimensions. Before image
  or canvas allocation it limits the 2x raster to 4,096 pixels per side and
  8,388,608 pixels in total (32 MiB of raw RGBA pixels). Oversized diagrams
  follow the existing render-error path; no lower-resolution fallback is added.
- Mermaid's cache budget includes both retained SVG and PNG bytes. Its public
  `maxAggregateSVGBytes` parameter keeps its historical name for compatibility.

## Verification still required

The focused tests cover palette serialization/contrast, cache reuse and
invalidation, retained PNG accounting, authored colors, SVG dimensions and
raster admission. They are added here but have not been executed against this
reconciled baseline. Historical prototype results are not evidence for this
revision.

Changed Swift files pass strict lint and format validation. JavaScript syntax
validation passes for all three changed harness scripts. These are static
checks; they do not establish runtime or native export fidelity.

Before completion, run locked package tests, strict lint/format checks and the
pinned Release app build. Exercise real native preview in light/dark app themes
for Mermaid, D2 and Graphviz, then compare HTML/PDF export on the same artifact.
Include authored fill/stroke/background colors, transparent graph backgrounds,
negative SVG origins, twelve-slice pies and the D2 native white-background
regression. Required native/Release evidence remains open until recorded.
