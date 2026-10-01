# Issue #121 — Isolated preview loads and contained resource reads

## Owner summary

A late resource request must belong to the saved document revision that created it, never the next document's folder. Filesystem replacement must not redirect that request outside its approved directory. Implement one contained reader shared with Export, and immutable WebKit loads with bounded asynchronous work.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Original design remains in #125 history. Follow [README](README.md) and [readiness review](READINESS_REVIEW.md). No E22 source, active branch, save/recovery authority or editor model is changed here.

## Reconciliation and trust boundary

HTMLPreviewSchemeHandler.swift, HTMLPreviewView.swift and ExportResourceResolver.swift remain unchanged from the original audit. PreviewSchemeHandler has a mutable request, fixed document authority and MainActor Data(contentsOf:) after a separate path approval. Generation-only reload state and early scope release must change together with the reader.

Keep content JavaScript disabled, response-header Content Security Policy authoritative, meta policy defense-in-depth, and no remote resource/popup/download bridge. An authorized directory permits reading its current ordinary contents; this is not a sandbox against a same-user process deliberately placing secrets/hard links in that directory or changing allowed file bytes. Byte-count limits are not proof of decoded browser-media memory bounds.

## Shared API and ownership

Add Foundation/Darwin-only LocalResourceAccess, consumed by ExportService and the app. It owns descriptor acquisition/read/close; no Preview/Workspace/QuickLookUI or EditorCore dependency. Package/project declarations follow XcodeGen. New semantic interfaces:

- ResourceGrant is none, singleFile(FileLease), or directory(DirectoryLease). A lease owns an opened descriptor and identity; callers cannot close/extract the raw descriptor. A single-file grant cannot derive a parent-directory grant.
- ResourceReadRequest contains a directory lease plus a normalized relative reference, trusted byte cap and cancellation token. A requested-file snapshot uses the single-file lease directly, not an inferred parent.
- ResourceSnapshot contains immutable admitted bytes, opened-object identity, validated name and MIME hint. It never returns a URL for a later unguarded reopen. Its retained backing payload carries the outstanding-buffer reservation until released or explicitly transferred to an equally bounded consumer owner.
- ResourceReadError distinguishes denied/changedRoot/nonRegular/oversized/changedDuringRead/cancelled/unavailable/unsupportedEnforcement.
- ContainedResourceReader submits blocking metadata/open/read work to a bounded I/O executor. async or nonisolated spelling alone is not proof of leaving MainActor under Swift 6.2 compiler settings.

The app owns immutable HTMLPreviewLoadContext: random load ID, document ID/recovery lifetime, saved generation, source, resource grant and fixed policy. Mutable revocation/task/quota state lives in its owning registry, not inside a retargetable root object. Untitled or ungranted documents can render their main source with grant none; local subresources are denied without failing unrelated source content.

## Contained-read algorithm

Acquire the intended directory's real scope before acquisition and keep it through actual I/O. Canonicalize a legitimate root spelling once, open it, fstat and pin its directory identity. Detect a changed root name before admitting a later read and fail/reload deliberately; do not silently substitute another directory. The pinned descriptor remains the authority, not the pathname recheck.

Parse URL components once. Strip query/fragment structurally before decoding path components. Reject malformed escapes, NUL, injected authority, unsupported absolute paths and traversal above root. Normalize safe dot segments once; do not double-decode `%252e` or normalize away distinct Unicode filenames. HTML root-relative references are rooted at this load's directory, not `/`. Explicitly test encoded separators and names containing percent, ampersand, quotes and non-ASCII characters. Caller URL policy remains separate from low-level filesystem admission.

Preserve legitimate in-root symlinks using a canonical-target hint followed by strict root-relative constrained open. A canonical hint is NOT a read authorization. The security-bearing operation opens that relative path from the pinned directory using `O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH`, with the actual shipping SDK's symbols. No absolute-path Foundation reopen, component-walk fallback lacking ancestor-rename protection, hardcoded flag numbers or silent omission of flags is allowed.

Apple's inspected XNU `xnu-12377.1.9/bsd/sys/fcntl.h` publicly declares both constraints. That source fact does not prove an installed macOS 26 SDK/runtime implements the required race semantics. Run the probe below before integrating the reader. If enforcement is unsupported or inadequate, revise only this prerequisite; do not weaken callers to obtain a build.

The opened descriptor must identify a regular file. Nonblocking open prevents a substituted FIFO from hanging before this check. Check size before allocation and then perform overflow-checked bounded reads, stopping at cap+1 and checking cancellation between chunks. Handle EINTR/short reads explicitly. Use the same descriptor for metadata, bytes and hashing. Close exactly once on its owning worker; cancellation must not close a reused descriptor number from another thread.

Check relevant metadata before/after reading and reject observed changes. This detects ordinary concurrent modification, not an atomic filesystem snapshot or cryptographic proof that an adversary never changed bytes between checks. The read boundary guarantees constrained object acquisition; the returned immutable Data then represents the bytes actually admitted. No bytes reach the consumer before admission succeeds.

### RESOURCE-OPEN probe — first executable unit

Compile the exact flag-based open on the shipping SDK and execute it on minimum supported macOS 26 and a current supported patch. In a real temporary tree, use barriers before constrained open and during reading to replace a leaf with an outside symlink, replace an intermediate directory, rename an ancestor, replace the root, create a FIFO, grow a file past the cap, and cancel. Include positive ordinary-file and safe in-root-symlink controls. Outside sentinel bytes must never be returned. Descriptors/scopes must return to baseline after failure. Record SDK/OS, syscall/error and sentinel checks, not only test names. Test hooks sit around the real syscall; injected fake reads are not containment proof. This architecture has not executed that probe.

## Immutable WebKit lifecycle

Use a stable NSView host with a replaceable child WKWebView. Each accepted saved revision creates a fresh configuration and handler bound to one context. The unguessable authority is `macdown-preview://r-<uuid>/`, not a path prefix that breaks root-relative CSS. Scheme, exact authority, port/userinfo and navigation policy are checked for every task; any preview-scheme URL is not automatically authorized.

A render identity combines document/recovery lifetime, saved generation, resource-root identity and load ID. Bind returned WKNavigation identity to that tuple and view identity. Old finish/failure callbacks cannot complete or rearm another load. Save As with identical text generation but different root reloads. Cancelling a debounced dirty generation rearms the gate for the next permitted clean request.

On supersession revoke old admission first, cancel its task records, stop/remove the old view, and replace it. Keep at most current and one transitioning view; do not retain every past revision. In-flight worker leases may drain independently after their WebKit references are released. No new reads start for retired contexts. Scope/descriptor ownership ends only after admitted work actually drains, never merely because the UI stopped waiting. Disposal is idempotent.

## Task and quota state machines

MainActor records WebKit task identity plus a unique operation token: admitted -> queued -> reading -> delivering -> finished/failed; stopped is terminal from every nonterminal state. Workers receive only Sendable inputs and return bytes/errors, never WKURLSchemeTask. Before EVERY callback verify the record/token/context is live, including after reentrant didReceive callbacks. stop removes/revokes first and performs no failure/finish callback on an already stopped task. One exact-once consumer terminal path revokes delivery and initiates cleanup; it does NOT immediately refund reservations for work or buffers still alive.

Choose one bounded I/O admission service for this reader: initially four actual active reads app-wide and two per preview context; at most 32 queued requests per context, with a bounded global queue. Fair admission prevents one window from starving another. A cancelled blocking read retains its worker slot until completion; never spawn unlimited replacement workers behind a timeout.

Trusted preview policy initially allows 16 MiB per resource, 64 MiB admitted resource payload and 512 requests per load. Those are proposed defensive values requiring Release calibration, not new measured passes. Charge request count at admission, including failed/repeated requests. Reserve the maximum permitted read bytes BEFORE enqueueing/awaiting. Release unused allocation capacity only when the read can no longer allocate it; failed reads refund their remaining buffer reservation after their buffers actually drain. Successful payload bytes remain cumulatively charged for the load, so cache eviction cannot replenish an unlimited fetch budget. Separate outstanding-buffer reservation from cumulative-delivery accounting and check additions for overflow. Four simultaneous reads cannot each observe the same unreserved remaining 64 MiB.

### Reservation ownership after consumer termination

There are four independently observable lifetimes, not one ambiguous finished flag. The consumer record controls permission to deliver; the worker lease controls an actual running syscall/job; the payload lease controls retained app-owned bytes; the load ledger counts all successfully delivered bytes. Stopping a scheme task ends only its delivery permission immediately. Cancelling queued work can release its reservations after removal from the queue is acknowledged and no worker can claim it. Cancelling running work retains worker and buffer reservations until the job really finishes and its buffers are dropped.

A successful read releases its worker slot when I/O ends, but transfers its payload reservation with the immutable snapshot into queued delivery or a cache; that reservation is not refunded merely because the read function returned. Transfer between reader and Export/Preview budget owners must be atomic with respect to admission and must never leave retained bytes uncharged in both owners. Multiple references to one immutable backing allocation share one reservation; a physical copy/encoding expansion requires separate reserved capacity. Descriptor/security-scope lifetime may end after actual I/O even if detached immutable bytes remain cached.

Cleanup is driven by the surviving admission/lease owner, not a continuation on a cancelled or deallocated UI task. It must complete exactly once without retaining the old WKWebView or invoking its stopped task. Keep retired accounting records until their last lease drains, even though their delivery registry was removed. WebKit/framework-internal copies and decoded media remain separate measured memory risks; these app-owned counters do not claim control over the browser's heap.

Add deterministic tests that suspend a real/admitted worker after allocating its buffer, stop/dispose the consumer, and attempt replacement admission. The UI is terminal but its charged bytes/slot remain until released. Also hold a completed snapshot in a cache, repeat start/cancel across many load IDs, release references out of order and inject duplicate completion. Assert no early refund, negative count, double release, illegal callback or artificial capacity increase. These tests supplement rather than replace the real filesystem containment probe.

Bound main-source hardening/encoding before WebKit load under an explicit rich-preview source policy; oversized HTML stays available in source mode with a localized explanation. Do not block file opening or silently truncate authored bytes. Measure WebKit decoded-resource behavior separately, including compressed image/media fixtures; input-byte caps do not prove renderer RSS or a hard total execution deadline.

## Response semantics and compatibility

Build response headers explicitly: correct Content-Type from admitted main/source or validated resource type, charset only when known, plus authoritative CSP and other existing hardening headers. The current generic response path does not supply MIME metadata, so this is an explicit implementation requirement rather than an assumption that it already works. HTML/CSS/fonts/SVG/XML/media must not all become text/html. UTF-8 HTML receives meta hardening; non-UTF-8 payloads retain bytes and response-header protection.

Main source failure produces a local load diagnostic/retry; denied/broken subresources do not erase the main page. Preserve saved-only reload semantics, readable code and source/rendered controls. New user-visible strings use correct catalogs/accessibility labels. Keep allowed fragment and local-document navigation compatible; fresh views must restore an explicitly supported view position without letting an old navigation authorize new paths.

## Tests and implementation sequence

A. RESOURCE-OPEN probe and LocalResourceAccess value/reader/limit tests. No caller refactor before a real containment pass.
B. Immutable contexts, capability variants and replaceable host; identity/reload/scope-lifetime tests.
C. Async registry, quotas and MIME delivery; deterministically race concurrent reservations, cancellation before queue/start/read/delivery, reentrant stop, duplicate completion, disposal, no-root and two-window cases. Include separate worker/payload/delivery lifetime assertions above.
D. Real WebKit hostile-content and Release UI evidence via #88. #118 may consume tested A without waiting for unrelated preview UI evidence. E23 cannot create a second reader or infer a directory grant.

Retain the complete #121 corpus: remote HTTP/HTTPS images/styles/fonts/media/CSS URLs; file/data/javascript top-level navigation; frames/object/embed/base/form/meta refresh; popups/downloads; fake head tags in comments/rawtext/attributes; non-UTF-8 HTML/SVG/XML; rapid save/switch/close; scope and worker cleanup. Observe actual network denial independently of CSP string contents. Run serial format/lint, affected package/app suites, full regression and Release app build. Native GUI evidence is still required.

## Review disposition

Second review fixed absent/file/directory capability confusion, immutable-state versus mutable-revocation ownership, quota oversubscription across awaits, callback reentrancy, missing MIME assumptions, cancelled-worker slot leakage and overclaims about snapshot/decoded-memory guarantees. The continuation review additionally separates consumer termination, actual worker drain, retained payload ownership and cumulative delivery; neither cancellation nor a returned read function means every reservation may be released. SDK/kernel and live WebKit behavior are named execution gates, not waived or asserted. #121 closes only with its full acceptance evidence in #115.

Primary references inspected: https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/sys/fcntl.h and https://docs.swift.org/latest/documentation/swift/task/cancel%28%29/ . Apple WKURLSchemeHandler lifecycle documentation remains the API authority; use the installed SDK for exact signatures.
