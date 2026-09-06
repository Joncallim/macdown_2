# Post-1.0 extension API — design notes (not implemented)

This document is the issue #15 / EPIC-14 deliverable "possible post-1.0
JavaScriptCore extension API design document." It describes a plausible
shape for a **future**, third-party-facing extension mechanism. **Nothing
described here ships in MacDown 2 1.0.** No loader, no `JSContext`
integration, no extension manifest format, and no public API surface exists
in the codebase as of this document. This is design-only, per issue #15's
own scope ("design only, no third-party loader in macOS 1.0") and
`epic-14-implementation.md` §10/§17 Slice 8.

## Why this exists now, and why it ships nothing

EPIC-14 shipped two first-party extension seams:

1. **`Contributing`** (`Packages/MacDownKit/Sources/Contributions`) — trusted,
   in-process Swift that can contribute renderer-neutral derived content
   (Preview/Export both consume the same `ContributionResult`).
2. **Text-filter commands** (`Packages/MacDownKit/Sources/TextFilters`) — a
   local, unsandboxed subprocess a user installs themselves, invoked with
   structured arguments and bounded execution/output.

Both are real, but neither is a **third-party extension API**: the first
requires writing and shipping Swift inside the app itself; the second has no
way to register UI (a menu item, a palette entry) beyond what
`TextFilterCommandDiscovery` already surfaces, and no way to contribute
derived Preview/Export content the way a first-party contribution can.
A future third-party extension API — installable by someone other than the
user who wrote it, capable of contributing real content, and safer than an
arbitrary unsandboxed executable — is real, unstarted product surface. This
document exists so that surface is not designed from a blank page whenever
work on it actually begins, and so E19/E20/E21's own architecture passes
don't have to re-derive an answer to "should our renderer also be
extension-loadable?" without something concrete to react to.

## What such an extension could plausibly register

The most natural shape mirrors `Contributing` directly: an extension
registers one or more **contributions**, each declaring:

- an **activation trigger** (a marker syntax, analogous to `[TOC]`, or a
  document-wide pass);
- a **pure transform function**: given the parsed document (or a
  renderer-neutral subset of it — see "What the extension would NOT see"
  below) and matched source text, produce either a Markdown string (
  re-enters the existing Markdown-shaped rendering path both Preview and
  Export already use) or a self-contained HTML fragment (the `.html`
  `ContributionRepresentation` case E14 already reserves but does not yet
  handle, `epic-14-implementation.md` §18 residual risk 1);
- **diagnostics**, in the same renderer-neutral shape `ContributionDiagnostic`
  already defines.

This is deliberately **not** a general-purpose plugin API (no arbitrary
NSView injection, no direct AppKit access, no custom menu commands beyond
what a manifest declares). Scoping it to "produce derived content for a
document position, plus diagnostics" is what makes a JavaScript sandbox
plausible at all — a general in-process plugin host is the exact permanent
architecture this project already retired (see `epic-14-implementation.md`
§2.2's "the old NSBundle in-process plugin system is permanently retired").

A **manifest** (JSON, sitting beside the extension's JS source, discovered
the same way `TextFilterCommandDiscovery` scans a folder rather than via a
package registry) would declare: a stable extension identifier, a
human-readable name and publisher, the JS entry point, and which activation
trigger(s) it registers. No manifest field executes code by itself — only
the declared entry point does, and only inside the sandbox below.

## The sandboxing model

**`JSContext` (JavaScriptCore), not a subprocess.** Unlike text filters —
which deliberately accept full OS-level privilege because they are the
user's own local automation (`epic-14-implementation.md` §10) — a
third-party extension is code the *document's author* did not necessarily
write, so it needs a real capability boundary:

- **No filesystem access.** `JSContext` exposes no file APIs unless the host
  app installs them; none would be installed. An extension cannot read,
  write, or enumerate anything on disk, including the document's own file.
- **No network access.** Same mechanism: `JSContext` has no networking
  primitives unless the host provides them. Nothing is provided. This keeps
  first-party editing/preview/export's existing local-and-offline guarantee
  (`RELEASE_HARDENING.md`) intact even once third-party code can run.
- **No process/child-process capability.** Nothing resembling `Process` is
  exposed. An extension cannot launch a text-filter command, another
  extension, or anything else.
- **Bounded execution.** A wall-clock timeout per invocation (the same
  watchdog-vs-continuation shape `TextFilterRunner`/`PDFNavigationDelegate`
  already use, ported to whatever `JSContext` exposes for interrupting a
  running script — `JSContext.exceptionHandler` plus a forced-abort signal,
  confirmed against the real API when this is actually built rather than
  assumed here).
- **Bounded output.** The same "generated content has a byte ceiling"
  posture `PreviewContributionBudget`/`ExportResourceBudget` already
  enforce for first-party contributions would apply identically to
  extension-produced content — an extension does not get a larger or
  separately-tracked budget merely because it is JavaScript.
- **No DOM, no browser globals.** `JSContext` is a bare ECMAScript
  environment; nothing web-shaped is added. An extension author writes
  ordinary JS functions against a small, explicit host-provided API object,
  not against `window`/`document`.

**What the extension would NOT see:** raw AppKit objects, other open
documents, the filesystem, the user's editing history, or anything about
the app's own internals beyond the one document position it was invoked
for. The transform function's only inputs are the same renderer-neutral
shapes `Contributing` already uses (parsed structure/source text/range) —
never a live `MarkdownDocument` reference with more surface than a
sandboxed caller should have.

**What this model does not claim.** JavaScriptCore's sandbox bounds
*capability* (what the extension can reach), not *correctness* — a buggy or
adversarial extension can still produce wrong, offensive, or resource-heavy
(within budget) output for the one document position it was asked about.
That is the same "fault/result isolation, not a security boundary against
malice in what content it produces" posture `Contributing` already accepts
for first-party contributions (`epic-14-implementation.md` §10) — the new
guarantee this design adds is that a third-party extension additionally
cannot touch the filesystem, network, or another process, which trusted
first-party Swift does not need guarding against in the first place.

## Distribution and discovery

Not designed here beyond ruling out an in-1.0 loader. Real open questions
for whenever this is built, named so they are not silently assumed away:

- Whether extensions are discovered from a local folder (mirroring
  `TextFilterCommandDiscovery`'s "drop a file in, it appears" model) or a
  future signed/reviewed distribution channel — these have very different
  trust postures even under the same JS sandbox.
- Whether an extension identifier collision (two extensions claiming the
  same activation trigger) is a hard error, a declared-priority order, or a
  user-visible conflict the way MacDown 2 has not needed to solve for its
  own single first-party `ContributionRegistry.standard` list.
- Whether extension installation needs its own user-facing enable/disable
  UI (distinct from "Show Commands Folder"'s manual, no-UI posture for text
  filters) given that a JS extension is closer to app functionality than a
  local automation script is.
- How an extension's manifest-declared name/publisher is verified, if at
  all, before MacDown 2 displays it as that extension's identity.

## Relationship to E19/E20/E21

Math (E19) and diagram (E20/E21) rendering ship as **first-party** Swift
`Contributing` implementations, not as extensions built on this design —
this document does not change that. What this design *is* useful for is
confirming, before those epics' own architecture passes begin, that a
future third-party extension would plug into the same
`ContributionRegistry`-shaped seam those epics are already extending,
rather than requiring a second, incompatible registration mechanism
whenever a third-party extension API is eventually built. Nothing in E19's
or E20's own scope depends on this document beyond that shape check.
