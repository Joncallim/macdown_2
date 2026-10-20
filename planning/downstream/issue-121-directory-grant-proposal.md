# Preview directory ownership proposal (#121)

## Owner summary

A resource request from document A must never read document B's folder after a
save, switch or reload. The proposed design binds each preview to a retained,
explicit directory grant and an opened document-directory object. Stopping the
preview immediately prevents further delivery; actual reads keep their access
owner until they finish.

This is a reviewed **proposal, not an accepted production integration**. Opening
a single file currently lets preview infer its parent and load sibling assets.
The accepted #121 contract forbids inferring directory authority from a file
grant. The owner chose an explicit **“Allow preview resources”** action with a
folder chooser for a file opened on its own. The existing Open Parent Folder
alert does not itself prove an operating-system directory grant. This decision
does not grant access automatically or change the current editor behavior.

## Baseline and inspected facts

Inspected integration: `aaec07288f96348fa6de651554991a865f1e4e96`.
Local master: `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`.
The inspected panel, file-tree, workspace and LocalResourceAccess interfaces
match that master. This continues the [accepted handoff](issue-121-handoff.md)
and [delivery correction](issue-121-delivery-implementation.md); neither the
historical baseline nor callback revocation establishes resource ownership.

| Route or owner | What exists | Required reconciliation |
| --- | --- | --- |
| `NSFilePanelProvider.chooseFolder` | A directory-only open panel returning a URL | Preserve the selection's provenance and scope owner at this edge. |
| `chooseFile`, recent file, document open and Save As | File selection/bookmark and a file URL | No inferred parent grant. Save As must recompute the permitted resource base. |
| `WindowCoordinator+FileTree.presentRevealOutsideRootAlert` (Open Parent Folder) | App-level confirmation, then the inferred parent URL | User intent is not evidence of an OS folder-selection extension. Resolve this workflow before minting authority from it. |
| Recent folders and session restore | Security-bookmark resolution, then lexical/access URLs | Retain resolved directory authority and scope; URL equivalence is not sufficient. |
| `FolderOpenContext` and cross-window opens | Root/access URLs | Transfer a typed grant attachment with provenance; do not create authority from those strings. |
| `WorkspaceModel.folderURL` | Mutable document/folder association | Association is not permission. |
| `FileTreeModel.rootAccessScope` | Internal `FolderAccessScope`; the model exposes only its access URL. `FolderAccessScope.started` is public on the scope object. | Tree lifetime is not preview lifetime. Preview needs its own retained backing owner. |
| Root replacement/disappearance/rename | `setRoot` tears down; vanished root tears down; accepted rename replaces a scope outside that path | Revoke the old grant epoch before asynchronous work resumes. Cover direct rename/remap routes, not only `setFileTreeRoot`. |
| `LocalResourceAccess.DirectoryLease` | Pinned descriptor, identity and changed-name check; URL-based initializer | Add descriptor-relative child-directory derivation, not check-then-absolute-open. |

`WindowController.setFileTreeRoot` awaits a rebuild hook before setting the tree
root. Model association and tree state can therefore disagree during suspension.
Preview must receive a captured attachment, not consult whichever model/root is
current when a delayed task resumes.

`PhysicalFileIdentity.matches(URL, URL)` is a display/equivalence helper with a
lexical fallback even when obtained object identities differ. It must not
authorize a grant or child lease. Use the strictly compared identity obtained
from the opened descriptor. A missing identity fails acquisition rather than
falling back to pathname equality.

The inspected XcodeGen spec has no entitlement declaration.
`planning/MAC_SIGNING_BRIEF.md` §Step 2 and `planning/RELEASE_PATH.md` specify
Developer ID hardened runtime with **no app sandbox and no entitlements** as
the intended shipping configuration. The release script accepts an optional
`ENTITLEMENTS` override for an evidenced exception; it defaults to none.
These records settle the implementation intent, not the final signed artifact's
behavior. Likewise
`startAccessingSecurityScopedResource() == false` alone is neither directory
permission nor a universal denial: a valid route may not require a dynamic
scope. Record the authority route separately from the start/stop obligation.
Confirm the actual signed candidate's entitlements and resource behavior before
claiming operating-system permission acceptance; the folder-selection action
remains an app-level authority boundary in the intended unsandboxed build.

## Resolved file-only workflow (owner choice, 2026-10-20)

When a Markdown file is opened without an attached directory grant, render its
saved source but deny sibling image, style, font and media reads. Show **“Allow
preview resources”** beside the preview's resource-unavailable state. Activating
it presents a directory-only `NSOpenPanel` tied to that document's window.
Cancellation or panel failure leaves the preview ungranted and the source
available. Selecting a folder creates a new window-local grant attachment from
the panel result; it never upgrades the file URL or its inferred parent in
place. Rebuild the saved preview with a fresh load identity only after that
attachment has been acquired and checked. The chosen folder must contain the
document's intended parent directory under the contained-child contract;
otherwise explain the mismatch and leave resources denied. A selected folder
does not permit paths outside the document's own directory, including siblings
elsewhere under the chosen root.

The action is available again after a declined selection, changed root or
reopen without a valid retained grant. Save As to a different directory revokes
the old preview attachment before another read can start and requires a new
explicit grant unless a separately valid folder attachment already covers the
new document parent. A same-directory Save As still creates a new render
identity. A grant is attached to this window and document lifetime; closing
the window ends new admission, while already admitted reads retain their scope
until they drain. The action and failure copy need localised text, keyboard
access and VoiceOver labels. No document bytes leave the machine.

This resolves the product workflow and intended signing configuration, not the
remaining engineering gates: implement the panel-origin backing and child
derivation without a pathname fallback, then verify actual signed behavior,
scope lifetime, hostile resource reads and native UI behavior.

The preparatory `NSFilePanelProvider.choosePreviewResourceFolder(near:)` edge
returns a typed selection receipt with the originally requested document URL.
It requires a concrete target window for the sheet and does not fall back to a
different key window after suspension. It records the selected directory's
device and inode at the panel-return edge; a future backing must compare those
values to the opened descriptor before admission. It does not create a directory lease,
start a scope, grant access or change live preview behavior. The future caller
must reject stale document/window epochs, attach a retained backing and
complete the read-path integration before exposing the action.

`PreviewDirectoryGrantBacking` now implements the next isolated slice. It starts
the selected URL's scope, opens the root off MainActor, compares its descriptor
identity with the receipt, and pins the document directory through the root.
An admitted `Use` retains the backing after revocation; the last use closes the
descriptors and stops the scope. The backing is not attached to a window or
renderer yet. It does not implement the global read queue, payload reservations,
WebKit context or Textual loader, so no chooser or resource grant is exposed to
the user. Focused tests cover held-use drain, selected-name replacement and
an outside document; they do not replace native or signed-artifact evidence.

## Proposed interfaces and dependency direction

Names below express semantic contracts and are not existing APIs.

| Owner / value | Contract |
| --- | --- |
| App: `DirectoryGrantBacking` | Created only at a reviewed directory-selection or directory-bookmark edge. Owns provenance, a pinned root lease and the exact scope-start/stop obligation. Has no retarget operation. |
| App: `DirectoryGrantAttachment` | Window-local opaque grant ID and epoch referencing that backing. Controls new admission for that window. Sharing a backing creates a distinct attachment, so closing one window cannot revoke another legitimate window. |
| App: `DirectoryGrantUse` | An admitted use retains the backing through acquisition and actual I/O. Revocation prevents new uses; existing uses release exactly once after work drains. It does not retain a view or scheme task. |
| LocalResourceAccess: contained child acquisition | Receives a pinned root and parsed relative document-directory reference. Opens from the parent descriptor using SDK-supported containment flags, verifies a directory with `fstat`, and returns a distinct lease with strict identity/name guards. |
| App: `HTMLPreviewLoadContext` | Immutable load ID, document/recovery identity, saved generation, source, derived resource grant and policy. No closure that looks up a current document, folder or handler request later. |

The app already consumes FileTree and owns windows. It may depend on
LocalResourceAccess as the handoff specifies, with declarations through
`project.yml`. Do not add a FileTree-to-LocalResourceAccess dependency merely to
borrow FileTree's scope. FileTree and preview may share an app-owned permission
backing through an explicitly reconciled API, or retain separately acquired
uses; either approach must pair each actual scope start/stop correctly.
LocalResourceAccess stays Foundation/Darwin-only.

A single-file grant may snapshot that file. It cannot derive a directory.
Untitled/ungranted main source can render with `none`; denying sibling assets
is a visible compatibility change, not an implementation detail to slip in.

## Mapping and state transitions

1. At a reviewed folder-authority edge, acquire and pin the intended root while
   its scope is held. Validate the opened object against the intended strict
   identity. A pathname match never substitutes for that comparison.
2. Attach the backing to the window with a fresh epoch. Capture that attachment
   before any asynchronous acquisition, rebuild or load scheduling.
3. Derive the document's parent from the pinned root using a contained relative
   operation while holding an admitted use. The document directory gets its own
   pinned descriptor. A workspace root plus a string prefix is insufficient:
   replacement of a nested document directory must not silently retarget it.
4. Preserve document-relative behavior: `/image.png` is relative to this
   document directory, not the workspace root. A symlink escaping the document
   base to a sibling in the workspace is not automatically allowed.
5. Recheck the attachment epoch before publishing the derived context. Retired
   acquisition may drain but cannot attach to a new preview.
6. Each saved render creates a fresh handler/configuration/view beneath a stable
   host, with the handoff's unique authority. A delayed A task can only reach A's
   immutable context, or be rejected. It cannot consult B.
7. Root replacement, disappearance, accepted rename, document Save As, close or
   disposal revokes old admission before yielding. Rename requires a new
   attachment/context after deliberate reacquisition; changing a URL on the old
   backing is forbidden. Do not automatically turn a resolved new path into a
   new grant.
8. Retired workers retain their uses until actual completion. Descriptors and
   scopes close only after the last use drains; detached immutable payloads keep
   their separate byte reservation. Closing one window leaves other live
   attachments intact.

Child acquisition must retain parent descriptor use during the real constrained
open, `fstat` and handoff. Canonical paths may provide hints and detect a changed
name, but cannot authorize an absolute reopen. The existing root guard alone
does not cover a replaced nested document base. Root and child name checks are
strict, supplemented by the pinned objects and containment flags.

## Invariants and failure behavior

- No bare file, parent, workspace association or access URL creates authority.
- No mutation of a load's root, source, policy, identity or authority.
- Root replacement before child acquisition either fails changed-root or stays
  beneath the original pinned root; it never opens the replacement by path.
- New admission fails immediately after attachment revocation. Late completion
  cannot publish a context or deliver callbacks, including reentrant callbacks.
- Single-file and absent grants never gain directory access through retries.
- Existing legitimate in-base symlinks remain supported by the handoff's strict
  canonical-hint/constrained-open strategy; outside targets are denied.
- Missing/changed roots and denied subresources do not erase main source.
  Restore/retry prompts must not widen permission without the reviewed user
  action. Any new prompt/string needs localization and accessibility coverage.
- Cancellation does not refund a live worker, scope or retained byte allocation.
  The handoff's admission/worker/payload/ledger quotas remain binding.
- Dirty-generation cancellation, Save As with unchanged text, exact navigation
  identity and one-crash recovery must survive the host/context refactor.

## Temporary-fixture verification plan

All filesystem fixtures are newly created temporary trees with distinct A, B
and outside sentinel bytes. No user documents or real bookmark store are used.

| Control | Required observation |
| --- | --- |
| Delayed A request after B is installed | A bytes or denial; never B bytes. Preserve the currently failing retained reproduction as the baseline. |
| Root replacement before/after child admission | Changed-root or original pinned object; never replacement sentinel. |
| Nested directory or ancestor replacement around the real open | No outside bytes; strict object identity and syscall/error recorded. |
| Same spelling with a different opened object | Rejected without `PhysicalFileIdentity` lexical fallback. |
| Ordinary files and permitted in-base symlinks | Correct bytes/MIME; document-relative and root-relative references preserved. |
| Sibling/outside symlinks, traversal and encoded separators | Denied; no outside sentinel. Double encoding and Unicode names keep existing parser semantics. |
| Queued acquisition revoked before start or publication | No new context, no callbacks and no revived epoch. |
| Two windows sharing one backing | Closing one revokes only its attachment; the other's valid reads continue. |
| Root disappearance and accepted rename/remap | Old epoch revoked even on paths bypassing `setFileTreeRoot`; reacquisition is explicit. |
| Held real read across stop/dispose | Scope and descriptor remain alive until worker drain; callback permission ends immediately. |
| Scope acquisition failure and unused-scope case | Provenance and actual OS configuration determine admission, not the start Boolean alone; exactly paired successful starts/stops. |
| File-only, untitled and Save As | Approved compatibility/permission behavior, main-source retention and root identity covered. |
| Dirty save/retry/process recovery | Existing coordinator and delivery regressions pass after host replacement. |

Synthetic scope counters prove ownership transitions only. They do not prove OS
sandbox enforcement. Execute real scope behavior under the intended artifact
configuration after that configuration is established. The retained
RESOURCE-OPEN evidence covers its recorded macOS/SDK and actual controls; it
does not establish macOS 26.0, other filesystems or unexecuted race schedules.
Native hostile-content/network observations, full regression, serial Release
validation and owner review remain required for #121.

## Independent review and disposition

The independent reviewer traced the current grant routes and found the proposal
technically plausible but **not ready for production integration**. The review
required window-local attachments, strict descriptor identity, child derivation
and scope drain, and identified the lexical-identity fallback and root rename/
disappearance paths above. No production permission changes or test execution
were performed during that review.

The intended OS-access configuration is recorded in the signing brief, and the
owner resolved the visible file-only workflow above. The actual signed
candidate has not passed that configuration's native permission checks. The
contained-child technical spike can be developed independently, but cannot be
presented as complete preview isolation.

Status: the file-only product workflow and intended OS-access configuration are
resolved; actual signed behavior and the production permission model remain
unverified. Preserve the local
callback/navigation corrections and the root-confusion failure. Do not claim
complete preview isolation until the signed configuration, grant integration
and native acceptance evidence pass.
