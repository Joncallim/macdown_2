# Issue #118 — Safe, bounded and verifiable HTML/PDF export

## Owner summary

Export should either produce a complete, bounded document or leave the previous output usable. The user must see what a slow PDF export is doing and cancellation must never publish a half-finished replacement. Local images cannot escape the authorized resource directory during a filesystem race. Companion assets must recover from interrupted exports without treating arbitrary user files as disposable.

This is an architecture hand-off, not a completed fix. Reviewed baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. Implement after reconciling post-E22 master. Do not alter E22's parser-option decision, editor slices or active PR. Consume #117's immutable export snapshot and #121's `LocalResourceAccess` reader. #113 may move the orchestration into DocumentPresentation; there must still be only one implementation of these policies.

## Baseline and stale assumptions

Inspected ExportResourceResolver, ExportResourceBudget, ExportHTMLWriter, ExportFileWriter, ExportCoordinator, PDFExportAdapter and PDFExportAdapterTests. #118 had no comments. PR #114 is already merged (`d8b857a271c1932f6299519204e42a64353929ab`); do not reopen it or describe its as-built reconciliation as pending.

The actual PDF adapter already sets `showsProgressPanel = true`. Its system progress panel is not evidence of complete-operation progress or correct cancellation. The adapter still uses synchronous `NSPrintOperation.run()`, reads/validates output on MainActor, and lacks a cancellation checkpoint immediately before promotion. The navigation watchdog does not itself stop WebKit.

ExportHTMLWriter embeds a resource at every matching occurrence, but the manifest budgets count each distinct resource once. Repeating one large image can therefore multiply the final HTML far beyond the distinct-resource total. Its reserve-capacity calculation is not a final-size gate. ExportFileWriter's current marker creation can overwrite an unfamiliar marker, and there is no implemented cleanup in the inspected writer: prose about reserved ownership is not crash-recovery proof.

## Journeys, scope and invariants

Cover ordinary companion HTML, strict self-contained HTML, and PDF using the same source/contribution semantics. Export an image-heavy document, cancel during preparation, cancel during print where the system permits it, retry after a failed write, and alternate companion/self-contained modes into the same destination.

Preserve the documented raw-HTML differences between destinations; this issue is not an arbitrary HTML sanitizer. Never read through a freshly reopened path after resource admission. Never modify authored source, encoding or recovery state. Never delete unknown files or widen filesystem/network entitlement to make an export succeed. Do not claim crash-proof multi-file transactions. Retain resources-before-primary publication and make crash recovery explicit instead.

## Interfaces, ownership and operation lifecycle

ExportService owns preparation, byte budgets, HTML assembly, companion ownership and publication policy. The app owns the WebKit/print adapter and accessible operation UI. LocalResourceAccess owns actual contained reads. DocumentPresentation, when introduced by E23, orchestrates these existing components and consumes an immutable `ExportSnapshot` from #117.

Add semantic types `ExportOperationID`, `ExportPhase`, `ExportOperationState` and `ExportDestinationLease`. Phases are selectingDestination, preparing, assembling, layingOut, printing, validating, publishing and terminal. Store operation state on the captured originating controller, not on an ephemeral ExportCoordinator value or current key window. One finish function releases guards exactly once. Keep the existing per-document reentrancy guard from command dispatch through every terminal path.

After the panel accepts a destination, acquire an in-process destination lease covering both the primary output and companion namespace. Keys use the opened parent-directory identity plus normalized destination leaf name; existing output identity also participates where aliases are observable. Different documents targeting the same primary or assets directory cannot publish concurrently. Reject source-document aliases and collision with another open authoritative document rather than overwriting editing state through an export path. This lease does not claim exclusion against arbitrary external programs; revalidate observed destination changes before promotion and report conflict instead of silently ignoring them.

The operation snapshots source, generation, document URL, theme, parse policy and derived-content inputs once, before the first render await. The export is explicitly of that snapshot; subsequent typing does not splice a new source into old contributions. Source-directory access remains leased for the read phase even if the editor window changes state. Closing the origin requests cancellation and must not redirect panels or alerts to another document.

## Final-byte budget and assembly algorithm

Retain all existing source/resource/contribution/prepared-HTML ceilings unless measured evidence supports a reviewed change. Add one final artifact ceiling to the trusted policy. Initial proposed ceiling: 256 MiB of UTF-8 assembled HTML, including template, stylesheet, embedded resources and destination hardening markup. It is a design limit to calibrate, not a performance promise; lower it if Release measurements require it. PDF input HTML obeys the same final limit. PDF output receives its own checked output-byte ceiling before loading it into PDFKit.

Make bounded assembly throwing. It must check overflow and the final encoded byte count before allocating a large result or writing any output. Base64 size is `4 * ceil(byteCount / 3)`, with checked integer arithmetic, plus MIME/prefix overhead. Count every emitted occurrence, not only manifest entries. A document referencing one image 1,000 times is 1,000 expansions. Include escaped metadata/template bytes and generated style/head content in the count.

Use the existing single-pass assembly structure, but append through a checked UTF-8 sink. Do not repeatedly rebuild the whole String per image. Cache at most one admitted data URI per distinct resource, and stop before an append would exceed the final limit. The preliminary size pass and actual sink must agree; the sink remains authoritative. Add cancellation checkpoints between bounded chunks. Return immutable final Data or stream into an exclusively-created sibling temporary file; callers must not construct a second unbounded String merely to measure it.

Tests inject tiny budgets at the trusted policy seam; public callers cannot bypass the production safety policy. Resource MIME/rewrites remain canonical. Do not blindly replace a newly invented placeholder in arbitrary raw HTML; preserve existing composition tests and restrict any new replacement mechanism to registered generated resource references.

## Contained resource snapshots

Replace ExportResourceResolver's canonical-path-then-Data read with #121's contained reader. Pass the export-specific limit and collect immutable resource bytes/identity from the descriptor read. Preserve supported in-root symlinks through the reader's reviewed canonical-hint/constrained-open path. Unresolved ordinary HTML resources retain the documented warning behavior; strict self-contained/PDF admission retains its fatal-resource policy.

Keep cmark's transient accumulator on one background executor. Do not suspend a mutable cmark traversal across actor hops. Either preload the bounded admitted resource references before the walk or run the reader's synchronous internal operation on the same bounded export worker; the application entry remains asynchronous and never runs filesystem reads on MainActor. Use one implementation of the low-level open/read boundary, not a second 'equivalent' Foundation reader.

## Managed assets and crash recovery

Treat an existing assets directory as unowned unless its marker/version is recognized. Do not overwrite an unknown marker, adopt an arbitrary nonempty directory or follow an assets-directory symlink. An empty directory may be adopted only after checking it remains empty under the pinned destination directory. Preserve all unrelated files even inside a valid managed directory.

Introduce a versioned ownership manifest containing relative leaf names, content hashes, resource types and the last committed primary digest, plus a small pending-operation journal. Generated leaf names are validated, not interpolated paths. Journal each owned temporary file before creation; use exclusive creation and no-follow operations. A broad '*.tmp' glob is never proof of ownership.

Publication order: validate destination and ownership -> write journal -> write/verify new immutable content-addressed assets -> atomically publish primary -> commit the ownership manifest -> remove only journal/manifest-owned obsolete files whose current bytes still match their recorded hashes. Keep both old and new asset sets until primary promotion is known to have succeeded. Cleanup failure is a precise nonfatal warning after a valid primary, not a false 'nothing was written' failure.

After a crash, reconcile pending journals against the actual primary digest before deleting anything. A successful later export can retain required active assets and clean only verified obsolete owned entries. Unknown, modified or symlink-replaced entries are retained and reported. For legacy v1 directories, preserve ambiguous files; build v2 ownership from resources actually verified/reused by the new export and record which legacy entries cannot safely be attributed. Do not invent an inventory for v1 files merely from their filename shape.

Chosen mode-switch policy: retain at most the one existing sibling assets directory when a self-contained/PDF export does not need it; do not recursively delete it. A mode switch creates no new assets or new directory. Subsequent companion exports reconcile the owned inventory. Enforce a total retained-owned-byte/count ceiling, including crash journals/orphans, before admitting more data; if unknown legacy residue prevents safe bounded growth, refuse new companion writes with a cleanup/recovery diagnostic rather than deleting unknown files. Test 100 alternating exports with changing resources and interrupted writes; managed storage cannot grow indefinitely. Exporting to different user-selected basenames intentionally creates different outputs and is not treated as one growing hidden cache.

## PDF progress, cancellation and publication

Show indeterminate preparation/assembly/layout progress, then system print progress, then validation/publication feedback. UI state remains owned by the same operation through all phases. All new labels/errors use String Catalogs; progress has an accessibility label and does not announce every transient tick.

Use `NSPrintOperation.runModal(for:delegate:didRun:contextInfo:)` with the captured origin window and a retained exact-once continuation bridge. Keep WebKit and AppKit operations on MainActor; do not dispatch an NSView print operation onto an arbitrary background queue. Do not assume the callback API makes pagination nonblocking: measure event-loop responsiveness during the actual print phase. Preserve the system progress panel. The Apple callback's false success value means cancellation OR error, so distinguish only when supported evidence exists; otherwise report that printing did not complete without claiming a successful cancellation.

Cancellation before printing cancels composition/layout and stops WebKit. During printing, use only a verified public system cancellation route. Do not call undocumented abort selectors or destroy a printing view. If the running phase cannot be cooperatively aborted, retain its resources, mark cancellation requested, communicate the phase accurately, and discard its temporary output after the system finishes. A cancelled operation must check its terminal state before validation and again immediately before primary promotion. Once atomic publication commits, report completion rather than retroactively claiming the published artifact was cancelled.

Move bounded PDF-file read, hashing, output-size checks and non-UI validation off MainActor where the involved API permits it. Keep PDFKit object confinement explicit; never transfer a mutable PDFDocument across actors. Any unavoidable main-actor validation is measured separately. Retain the WebKit view, navigation delegate, print operation and temporary output until their actual terminal callback; a UI timeout alone must not free resources still in use.

The layout watchdog, failure callbacks and task cancellation share one terminal function which stops the appropriate load and resumes once. An external test-process watchdog is required for a stuck AppKit print loop; a MainActor Task.sleep watchdog cannot rescue a blocked main thread. A measured system interval may be documented, but this architecture does not promise a hard deadline the API cannot enforce.

## Evidence and adversarial matrix

Unit/integration: all budget boundaries at limit-1/limit/limit+1; integer overflow; repeated single-image embedding; aggregate distinct resources; invalid MIME/reference; cancellation at each phase; changed destination; two windows targeting one output; primary equal to source; unknown marker/user files; symlink assets directory; journal crashes before/after every publication boundary; mode switching and retained-byte ceiling.

Use real race tests from #121 for resource containment, including outside-root sentinel bytes. Run the current FidelityCorpusTests plus #116 math and #117 anchors with E22's actual final block-directive policy. Record deliberate destination differences explicitly rather than comparing raw HTML strings and declaring any difference a bug.

Replace the PDF tests' 'temporarily remove .disabled' instructions with #88's explicit interactive test lane. The lane must fail if the PDF tests are unexpectedly skipped. Execute the genuine WebKit -> print -> PDFKit test, verify representative text on every relevant page, no clipped code/table/image/diagram content and correct print contrast. Page count alone is insufficient. Exercise both exports through actual menu/save-panel UI, cancellation and overwrite failure. Capture final PDF/HTML hashes and inspect the output independently.

Measure Release source sizes, resource counts/bytes, cold/warm total duration, phase durations, main-thread stalls, peak memory and final output size for 1 MiB ordinary text, technical documents and boundary fixtures. Freeze measured policy in one definition and add regression fixtures. No numerical PASS is supplied by this architecture.

## Implementation order, allowed files and stop conditions

1. Consume #117's immutable export request/origin contract and #121's reader. Allowed: ExportService preparation/resource paths and app ExportCoordinator; no E22 ownership changes.
2. Add bounded assembly and artifact budgets, with tests before writer changes.
3. Add manifest/journal ownership and crash-safe primary-last recovery. Stop if a cleanup path requires deleting unknown data or weakens the previous-output guarantee.
4. Add operation UI/state and the PDF bridge, with controllable failure/cancel tests followed by actual system printing. Stop on unsupported cancellation assumptions or a responsiveness failure requiring a different rendering architecture.
5. Execute parity, release calibration and GUI/PDF evidence; reconcile #115 and the E12 as-built notes.

Run serial format/strict lint, affected ExportService tests, app PDF/state tests, full package suite and Release app build. Use the documented XcodeGen project and #88's separate interactive lane. No production release authorization follows from these commits alone.

## Self-review and definition of done

Review corrected: stale 'no progress panel' wording; final-size amplification despite manifest deduplication; cancellation after print but before promotion; different-window destination collisions; unknown marker adoption; deleting assets still needed by the old primary; recovery after primary success but before manifest commit; and using a main-thread watchdog to claim a hard print bound.

#118 is complete only with every issue criterion mapped to actual passing evidence. The shared reader's runtime proof, real print behavior and calibrated limits remain required implementation gates. PR #114 is already resolved; no criterion is closed merely because this hand-off exists.

## Primary reference

Apple NSPrintOperation callback and success semantics: https://developer.apple.com/documentation/appkit/nsprintoperation/runmodal(for:delegate:didrun:contextinfo:)
