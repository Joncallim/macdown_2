# Issue #441 — cursor ownership boundary diagnostic

Date: 2026-10-14

## Scope

This checkpoint investigates the report that the I-beam cursor can remain
active over non-editor chrome. The intended boundary is:

- editor text: I-beam;
- Find-field text: I-beam;
- the editor/preview divider: its existing divider cursor;
- toolbar, sidebar, status bar, preview and other surrounding chrome: arrow.

No cursor override, selection change, or global arrow rule is introduced by
this checkpoint.

## Source evidence

The current source has no explicit `NSCursor`, `cursorUpdate`,
`addCursorRect`, or `setCursor` implementation in the app target or
MacDownKit Swift sources. The editor is an `NSViewRepresentable` whose
`makeNSView` installs the cached `NSTextView` inside an `NSScrollView`;
`FindBarView` and the rest of the shell are SwiftUI/AppKit-native controls.
Therefore the observed sticky cursor is most likely AppKit hit-testing/
cursor ownership across a representable boundary, or an upstream view that
claims the cursor, rather than an existing application-wide cursor policy.

## Reproduction status

Source inspection was completed on the integration head. A native desktop
reproduction could not be completed in this execution environment without
an available, safe interactive desktop session. Consequently there is no
claim here for native acceptance across document sizes, editor-only/split
layouts, scrolling/resizing, or tab/window changes.

## Safe next experiment

On an available desktop session, record the cursor after each transition in
both a short and large document:

1. editor text → toolbar/sidebar/status bar;
2. editor text → Find field → chrome;
3. editor text → divider → preview/chrome;
4. after scroll, resize, editor-only/split toggle, and native tab/window
   activation.

Use the view under the pointer (and its window hit-test ancestry) to identify
the owner before changing code. If an isolated owner is proven, add the
arrow cursor only at that chrome boundary and retain the editor, Find-field,
and divider-specific behavior. Reject any fix that relies on a global
`NSCursor.arrow`, changes selection, or masks a stale view/window lifetime.

## Residual scope

Issue #441 remains open pending real native reproduction and acceptance. This
document is diagnostic evidence only; it does not close the issue.
