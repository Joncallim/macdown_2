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
grant. Preserving that behavior while meeting the contract requires a deliberate
permission and user-experience decision. The existing Open Parent Folder alert
does not itself prove an operating-system directory grant. No folder permissions,
entitlements, editor behavior or production code change in this reconciliation.

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

The inspected XcodeGen spec has no entitlement declaration. This is not proof of
the eventual shipping app's sandbox configuration. Likewise
`startAccessingSecurityScopedResource() == false` alone is neither directory
permission nor a universal denial: a valid route may not require a dynamic
scope. Record the authority route separately from the start/stop obligation.

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

Remaining decisions: establish the intended OS-access configuration and choose
the visible file-only asset workflow (for example an explicit folder-selection
action, if approved). A reviewed contained-child technical spike can be separated
from that decision, but cannot be presented as complete preview isolation.

Status: product/authority contract unresolved, not an approval denial. Preserve
the local callback/navigation corrections and the root-confusion failure. Do not
integrate the proposed permission model until those decisions and their narrow
implementation contract are accepted.

