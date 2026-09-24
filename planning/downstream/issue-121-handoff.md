# Issue #121 — Isolated HTML preview requests and safe resource reads

## Owner summary

An HTML preview must only read resources belonging to the document revision that created it. A late image request from an old page must never borrow the next document's directory. Concurrent filesystem changes must not redirect an approved image read outside that directory. The design gives each load an immutable owner and replaces path validation followed by a separate file read with one descriptor-backed read boundary shared with Export.

This is deferred architecture, not implementation or release evidence. Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09` on 2026-09-24. Leave #112, PR #124, every E22 slice and `planning/epic-22-implementation.md` untouched. Reconcile the listed interfaces with post-E22 master before implementing. The issue's acceptance criteria remain authoritative.

## Baseline reconciliation

Read `HTMLPreviewSchemeHandler.swift`, `HTMLPreviewView.swift`, `ExportResourceResolver.swift`, `Package.swift`, `AGENTS.md`, `EPIC_STANDARD.md` and `RELEASE_HARDENING.md` at the baseline. #121 and #118 had no issue comments at review time.

`PreviewSchemeHandler.request` is mutable; both the main page and subresources use the fixed `macdown-preview://document/` authority. `serveSubresource` calls the path validator and then synchronous `Data(contentsOf:)` on MainActor. The coordinator identifies loads with a mutation generation, uses one pending generation and a fixed failing URL, and releases its previous security scope at the next load boundary. These assumptions must change together, not only the handler property. Export has a separate canonical-path/check/read implementation of the same boundary. The new reader is justified by these two real consumers; it does not belong in EditorCore.

## Journeys and invariants

A saved HTML document renders with readable local images/styles/fonts; typing unsaved changes continues to respect the existing saved-revision policy. Saving creates a new immutable load. Switching documents, moving a backing file or closing a window revokes the old load. Broken or denied resources do not compromise the main source page.

No content JavaScript, script bridge, automatic remote request, popup or download is introduced. Response-header Content Security Policy remains authoritative; meta-policy insertion stays defense in depth. No source text or FileCore state is changed by previewing. Security-scoped access follows actual I/O lifetime, not merely UI lifetime. No shared mutable 'current root' exists.

## Ownership and interfaces

Add `LocalResourceAccess` as a small SwiftPM target depending on Foundation/Darwin only, with tests. ExportService and the app consume it; it does not depend on Preview, ExportService, Workspace, windows or QuickLookUI.

Semantic interfaces (new, not existing symbols):

- `ResourceRootLease`: immutable opened directory capability, root identity `(device,inode)`, canonical acquisition name and revocation state. Descriptor ownership is internal; callers cannot extract or close the descriptor.
- `ResourceReadRequest`: root lease, normalized reference, trusted byte limit and cancellation token.
- `ResourceSnapshot`: immutable bytes, actual opened-file identity and size, validated relative name and MIME hint. No mutable URL is returned for a caller to reopen.
- `ResourceReadError`: denied path, changed root, unsupported safe-open mechanism, non-regular file, unavailable, changed-during-read, oversized, cancelled.
- `ContainedResourceReader.read`: asynchronous at the application boundary, with blocking filesystem operations dispatched to a bounded I/O worker, never inferred to be off-main merely because the function is `async`.

The app owns `HTMLPreviewLoadContext`: random load ID, document identity, saved generation, immutable source, root lease, policy and resource counters. An immutable context is installed into one handler and one WKWebView configuration. It cannot be retargeted.

## Safe-open algorithm

1. Acquire the authorized document-directory security scope, resolve its intended canonical directory, open a directory descriptor and verify its identity. Store this capability, not just its pathname. Acquisition and all metadata calls run off-main. When the original root name no longer identifies that root, fail closed or start a new explicitly authorized load; never silently substitute the replacement directory.
2. Parse a resource reference once. Remove URL query/fragment before decoding the path. Reject invalid percent escapes, NUL, absolute/authority injection and traversal outside the root. Normalize safe `.`/internal `..` without changing Unicode filename spelling. Bound path length and component count. Do not decode `%252e` twice. Root-relative HTML references map to this load's root, never the filesystem root.
3. Preserve the existing useful in-root symlink behavior: canonical resolution may identify an in-root target and derive its strict relative path, but that resolution is a hint, not permission to read. The security-bearing open is relative to the pinned root descriptor, with no-follow across the entire final relative path and beneath-root resolution. Do not reopen the canonical absolute path through Foundation.
4. Use the public Darwin `openat` constrained-resolution flags supported by the shipping macOS 26 SDK/runtime. Apple's published XNU `fcntl.h` defines `O_NOFOLLOW_ANY` and `O_RESOLVE_BENEATH`. The initial implementation gate must compile against the supported SDK and actually demonstrate rejection of leaf/intermediate symlinks and ancestor/root replacement on the minimum supported OS. Do not hardcode undocumented numeric flags, silently omit a constraint, or substitute `realpath` plus `Data(contentsOf:)` on failure. Unsupported enforcement is an explicit release-blocking result, not a weaker fallback.
5. On the opened descriptor, `fstat` must identify a regular file. Open nonblocking so a replaced FIFO/device cannot hang before that check. Reject directories, sockets and special files. Check size before allocation, then read in bounded chunks with overflow-safe counters and cancellation checks. Stop at the caller's limit plus one byte; a growing file cannot bypass the preflight size check. Never use an unbounded mapped read.
6. Verify opened-file metadata before/after the snapshot and reject observed mutation. Read and hash the same descriptor's bytes. Close that descriptor exactly once on its owning worker. Cancellation must not close a descriptor from another thread while a read can reuse its integer. No bytes are delivered to WebKit or Export until admission and byte limits pass.

The boundary authorizes objects reachable under an approved root at constrained open, not the historical provenance of every byte. It cannot protect against the same user deliberately copying secrets into an authorized directory or modifying a permitted file. Hard links do not prove exclusive pathname ownership. Do not claim this is a sandbox against arbitrary same-user code. Tests must nevertheless prove that symlink/path replacement cannot redirect a request to an outside-root target. If the runtime's constrained lookup does not satisfy the ancestor-rename test, stop rather than claiming a path-prefix check repairs it.

## Immutable WebKit lifecycle

Change the representable to a stable NSView container that owns a replaceable child WKWebView. Every accepted saved revision receives a fresh configuration, immutable handler and unguessable authority such as `macdown-preview://r-<uuid>/`. Using the authority rather than a path prefix preserves `/image.png` and CSS-relative resolution. Every navigation and scheme request must match that exact authority, scheme and permitted userinfo/port policy. Do not treat 'any preview-scheme URL' as authorized.

The coordinator's identity is `(documentID, savedGeneration, rootIdentity, loadID)`, not generation alone. Bind returned `WKNavigation` identity to that tuple. Finish/failure callbacks from an old view/navigation cannot complete or fail a newer reload gate. Save As with unchanged generation but a changed resource root must reload. Dirty-state cancellation must rearm a cancelled pending generation so the next clean update can load it.

At supersession, revoke the old handler before stopping/removing its web view. At most the current and one transitioning view may be retained. Old root leases remain alive only for admitted I/O that is draining; no new reads may start after revocation. Do not keep a process-lifetime dictionary of every past preview root. `dispose` is idempotent and balances each successful security-scope acquisition exactly once, after its descriptor work drains.

## Scheme-task state machine

On MainActor, keep task records keyed by task identity and a separate unique operation ID: `admitted -> reading -> delivering -> finished/failed`, with `stopped` reachable from every nonterminal state. Store WebKit objects only in this registry. Worker code receives Sendable inputs and returns a snapshot/error, never a WKURLSchemeTask.

`stop` first marks/removes the task and cancels its operation. It does not call failure or finish on a stopped task. On worker return, verify operation ID, context ID and live state. Check liveness before each response/data/terminal callback, including synchronous reentrancy. There must be no WebKit callback after stop/disposal and no double terminal callback. Remove state on every terminal path. Navigation-policy completion handlers also complete exactly once.

Retain correct MIME metadata and response CSP for every payload. UTF-8 HTML may receive the existing meta hardening; non-UTF-8 HTML/SVG/XML remain governed by the response header. Do not mislabel all resources as text/html or silently decode arbitrary bytes lossily.

## Budgets, cancellation and errors

Reader limits are supplied by trusted destination policy; #118 retains its export-specific budget rather than inheriting a smaller Preview limit accidentally. Establish one Preview resource policy with initial proposed limits of 16 MiB per resource, 64 MiB admitted payload per load and 512 resource requests. These are design ceilings to validate, not measured passes. Count repeated/failed requests as well as unique bytes so request storms cannot bypass the request cap. Bound queued reads and concurrently draining retired loads. Unrelated windows may make progress concurrently; no global lock surrounds an entire preview operation.

Cancellation stops queued work and discards late results. A synchronous filesystem syscall is not promised to obey a hard wall-clock deadline; never block the main actor waiting for it. A bounded I/O admission service prevents cancellation storms from spawning unlimited workers. Report admission exhaustion/slow unavailable resources as local failures, not whole-page failure or unbounded retry.

New user-visible load/resource diagnostics use the normal String Catalog pipeline. Existing source/rendered controls retain accessibility labels. This issue adds no export or editor behavior other than the shared reader contract.

## Tests and evidence

Add `ContainedResourceReaderTests` with real temporary directories and synchronization barriers between resolution, open, metadata inspection and read. Test outside leaf symlink, intermediate directory replacement, parent-directory rename, root replacement, in-root symlink, root path aliases, Unicode/percent names, malformed encoding, traversal, special files, growth past budget, cancellation and repeated descriptor cleanup. Use recognizable outside-root sentinel bytes and assert those bytes never reach the snapshot or response. Stress races supplement deterministic barriers; a stress run alone is not proof.

Add app-level handler tests with controllable reader completions: late A after B, stop before read, stop during delivery, failure then stop, duplicate finish, disposal and two windows. Assert callbacks and balanced resource leases, not only final screenshots. Update reload tests for same generation in different documents, same-document Save As root change and old WKNavigation completion.

Run real WebKit integration for header CSP, HTML/CSS/SVG/XML, remote URLs, fake heads in comments/rawtext/attributes, meta refresh, base/form/frame/embed, top-level file/data/javascript navigation, popup/download and relative resources. Observe network denial independently; merely setting a CSP string is not execution evidence. Final Release GUI evidence must cover saved reload, rapid switching, teardown and hostile files.

## Implementation sequence and boundaries

A. Implement and prove the shared descriptor reader plus minimum-OS constrained-open test. Allowed: the new target/tests and package product declarations. Stop on unsupported kernel enforcement or outside-root sentinel delivery.

B. Introduce immutable load contexts and the replaceable WebKit host. Allowed: HTML preview host/handler and its policy/reload tests. Preserve saved-revision semantics. Stop on required changes to FileCore save/recovery ownership.

C. Add asynchronous task delivery, limits and teardown tests. Stop on callbacks after stop, unbalanced scopes or unbounded retired contexts.

D. Execute WebKit/security and Release GUI evidence. #118 may consume the reader after A; it must not create a parallel implementation. E23 Quick Look may consume only capabilities actually granted by its sandbox, never infer access to a parent directory.

Use serial formatting/lint/build/test commands from `AGENTS.md`; run `swift test --no-parallel --filter ContainedResourceReaderTests`, the affected Preview/app suites, the complete package suite and a Release app build. Generate Xcode projects from `project.yml`; do not hand-edit generated projects. Run actual GUI tests through #88's release harness when available.

## Architecture self-review and completion

Review caught and addressed: tokenized paths breaking root-relative CSS (authority token instead); a unique URL alone not isolating an old page (immutable handler/web view); generation collisions across documents (full identity tuple); old failure callbacks rearming new loads (WKNavigation binding); task cancellation followed by illegal callbacks (terminal registry); early security-scope release (I/O-owned lease); size-check races (bounded descriptor reads); safe in-root symlinks being accidentally rejected as a regression (canonical hint plus constrained final open); and assuming newest kernel headers prove minimum-OS behavior (mandatory runtime verification).

Architecture review found no remaining known contradiction within this design. SDK/kernel enforcement, WebKit execution and performance remain implementation verification gates, not asserted facts. #121 closes only when all issue criteria pass and #115 receives exact evidence. Do not close it because this document was committed.

## Primary references

- Apple WebKit `WKURLSchemeHandler` and `webView(_:stop:)` documentation: https://developer.apple.com/documentation/webkit/wkurlschemehandler
- Apple XNU public flags, source inspected 2026-09-24: https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/sys/fcntl.h
- Apple XNU lookup enforcement: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_lookup.c
- Repository code links use the baseline SHA above; upstream source is supporting design evidence, not proof of the installed SDK or runtime.
