# Issue #79 — Coherent Mermaid, D2 and Graphviz presentation

## Owner summary

All supported diagrams must remain readable in light themes, dark themes and PDF. For macOS 1.0 the chosen, explicit policy is a neutral light diagram canvas inside the surrounding editor/preview theme. This is the neutral/high-contrast option allowed by the issue, not a promise that arbitrary authored diagram colors will be recolored to match every custom theme. Mermaid, D2 and Graphviz follow the same policy and preserve their native vector export.

E23 (#113) owns this work. Do not implement it as a competing theme feature or independently close E23. Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. Read/reconcile the final post-E22 theme/editor interfaces before code changes. #115 requires real proof; #79 is no longer deferrable cosmetic debt, as its 2026-09-21 issue comment states.

## Baseline

Read all three bundled `Resources/render.js` files and Theme/ThemeController. Their entry points currently receive only source. Mermaid initializes once with strict security and returns native SVG plus a WebKit-composited PNG; D2 and Graphviz return SVG consumed by native decoding and Export. None of these functions receives the context's foreground/background. Surrounding CSS cannot recolor baked PNG pixels or guarantee SVG label contrast.

Do not force Mermaid into native SVG decoding or disable its HTML labels as a shortcut: the repository's harness records real loss/misalignment of labels with those approaches. Preserve Mermaid's real WebKit raster preview and vector static export.

## Shared interfaces and fixed policy

Themes owns an immutable `DiagramPalette` with an opaque white canvas, near-black default text/stroke, neutral node fills, accent/secondary colors with tested contrast, and a versioned policy ID `neutral-light-v1`. All default colors are resolved before the renderer is invoked. Resolve this palette explicitly from the destination policy; do not continue passing arbitrary current-theme RGB values that the renderer ignores.

The three render-context adapters receive the same resolved palette and destination. Their JavaScript entry points take structured parameters, never interpolated executable source. Renderer packages may depend on Themes' value types or accept the serialized palette from their existing adapters; they must not import the app, settings UI or WindowCoordinator. E23 owns the one palette definition. No second palette registry belongs in this issue.

Default engine palette/configuration is pinned explicitly where the bundled API exposes it. At the first harness integration check, verify the exact version's option names against its bundled API and a real minimal render. Pin a light profile and block source directives from changing security settings. Do not invent numeric theme IDs or assume the current library default will remain light. If a renderer cannot accept a light profile without a new dependency/runtime, stop and return the narrow mismatch; do not silently switch execution engines.

Add an opaque neutral canvas to the actual returned artwork, not only the SwiftUI container. Use a proper SVG element inside the known root/viewBox or the renderer's native background option; validate dimensions and escape attributes. Mermaid's PNG is rasterized from the same final SVG. The SVG and PNG must therefore represent the same canvas and colors. Existing explicit author node/edge colors remain authored styling; low-contrast author styling is not falsely reported as app-theme compliance. The advertised guarantee covers defaults and first-party chrome.

## Cache identity and asynchronous publication

Key caches by renderer ID/version, source digest, resolved palette fingerprint/policy version, layout options, output kind and raster scale where relevant. The same neutral profile across two app themes may intentionally reuse output; do not rerender simply because an unrelated theme ID changed. Conversely, a real profile/renderer/scale change must not reuse stale artwork. Distinguish reusable content identity from `(documentID, generation, requestID)` publication identity.

Late completion after edit, profile change, tab disposal or cancellation cannot replace a newer image. Shared in-flight work may deduplicate identical renders, but cancelling one consumer must not cancel another consumer's active request. Stop/recycle a failed WebKit worker before returning it to the pool. Do not reset Mermaid global configuration in a worker while another request is rendering in that same page; one active render per page.

## Resource budgets and failure behavior

Keep supported renderers local/offline. Carry source-byte, output-SVG/PNG-byte, finite dimension, maximum pixel-count, deadline, queue and cache limits in one versioned renderer policy. Validate width/height before canvas allocation, not after PNG encoding. Count aggregate retained bytes, not only cache entries. A timed-out worker is evicted; asynchronous late completion is ignored. A TaskGroup race is not a hard deadline when it still waits for an uncooperative child.

E23's calibration fixtures determine final numerical limits before release. Preserve current limits until that evidence justifies a reviewed change; do not increase a five-second timeout to conceal a regression. A supported diagram that fails remains readable source with a localized diagnostic. Cancellation is not presented as malformed user input. WaveDrom remains rejected for 1.0, not added while touching this registry.

## Print and interoperability

The neutral canvas/default text profile also applies to PDF input, so a dark app theme cannot produce white labels on white paper. Retain true SVG in HTML/PDF, not a screenshot of the preview. Transparent export is not the default under this policy. CSS `@media print` alone is not evidence that already-rendered diagrams are legible.

For each engine, test default diagrams, long labels, edge labels, nested structures, explicit author colors and a large graph in four representative light/dark/high-contrast app themes. Verify SVG content, the actual native-preview result and genuine printed PDF. Check label presence, clipping, readable default foreground/canvas and consistent PNG/SVG content. Preserve accessibility source labels and fallback descriptions; graph semantics are not inferred from an image.

## Implementation sequence and allowed changes

1. Within E23's palette work, define DiagramPalette/policy and golden serialization/cache tests. Allowed: Themes and existing render-context adapters, not E22 editor behavior.
2. Update each harness/Swift renderer to accept structured context, validate dimensions and produce opaque, coherent artwork. Add real renderer tests before changing default presentation.
3. Update content/cache keys and stale-result/cancellation tests; verify single-worker configuration confinement.
4. Run the three-engine Release calibration and light/dark/print/100-cycle lifecycle corpus. Update #79 and E23/#115 evidence together.

Run format, strict lint, affected renderer/diagram tests, full package tests and the Release app build serially. Actual rendered screenshots/PDFs and renderer logs are required; a test asserting only that a color is present in JSON is not visual evidence. Stop on offline/CSP regression, missing labels, stale output, invalid dimensions or unbounded worker/cache growth.

## Self-review and completion

Review resolved the temptation to fix baked colors with CSS, to degrade Mermaid's renderer, to share mutable per-page theme configuration, to confuse theme IDs with actual palette identity, or to claim user-authored low-contrast styling meets default-theme contrast. The neutral policy is a deliberate bounded 1.0 decision. It does not authorize an unplanned full diagram theme editor.

This document is design evidence only. #79 closes when all three engines and print output satisfy the policy under E23, their limits are calibrated, and #115 records the actual artifact/test evidence.
