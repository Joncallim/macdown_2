# Issue #118 — Bounded export and recoverable publication

## Owner summary

Export either produces a complete bounded result or leaves the prior result usable. Repeated images cannot cause unbounded embedding; cleanup cannot delete unknown files; cancellation cannot publish an unwanted replacement. Keep ExportService's existing Markdown/cmark/contribution pipeline and the native PDF print path unless a measured platform probe disproves it.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md), [readiness review](READINESS_REVIEW.md), #117's snapshot contract and #121's reader. E22 retains parser-option/block-directive ownership. Implementation is downstream, not an edit to Claude's active E22 work.

## Reconciliation and invariants

The inspected resolver/writers/coordinator/PDF adapter are unchanged from the original architecture baseline. PR #114's as-built reconciliation is already merged. The PDF adapter already has a system progress panel; the missing contract is complete-operation progress/cancellation and measured responsiveness. It still runs synchronous printing and has no final cancellation checkpoint before promotion.

The manifest deduplicates resources, while embedResources replaces every matching pathname occurrence in a String. This both amplifies repeated images and can alter literal authored text containing a content-addressed resource reference. A final-size check alone does not fix the latter. Current marker creation can replace an unfamiliar marker, and v1 has no inventory-backed crash cleanup.

Keep authored source/encoding/recovery unchanged, preserve ordinary HTML versus strict self-contained/PDF policy, keep all first-party rendering offline, and never claim a multi-file filesystem transaction is atomic. Do not add an arbitrary HTML sanitizer. Original issue criteria, including real PDF/UI evidence, remain binding.

## Operation and snapshot ownership

ExportService owns composition, budgets, assets and publication. LocalResourceAccess owns actual contained reads. The app owns WebKit/print UI. E23 DocumentPresentation orchestrates these same implementations later; no second reader/anchor/stylesheet/render pipeline.

Use #117's synchronous ExportOrigin reservation and immutable snapshot captured AFTER panel acceptance from the still-matching live document. Phases: selectingDestination -> preparing -> assembling -> layingOut/printing when PDF -> validating -> publishing -> terminal. One operation token owns its guard, UI, resources and terminal state. UI stays on the initiating window, never ambient keyWindow. Origin closure requests cancellation without retargeting a sheet.

Source access is a leased explicit capability, not a URL-derived grant. Composition consumes the same source/theme/parse/generation values across every await. Reject export destinations aliasing the source or another currently open authoritative editor document unless a separately specified safe interaction exists; do not silently overwrite editing state.

## Publication admission and destination identity

Keep per-document command reentrancy. Additionally serialize the short destination publication/recovery phase per OPENED PARENT DIRECTORY identity `(device,inode)`, not guessed lowercased filenames. Compose/render independently; do not hold this directory lease through the save panel or expensive PDF work. This deliberately coarse publication lock covers `.html`/`.htm` same-stem assets, case-insensitive aliases and two windows without inventing a universal filesystem-normalization algorithm.

Revalidate chosen destination/parent and the captured existing-output revision under that lease before writing. An observed external change is a conflict; keep prior content. This in-process lock does not fence arbitrary external writers. Do not claim a precheck plus rename is a filesystem compare-and-swap. Reuse established conditional-publication mechanics when an exact expected revision must be protected; if that cannot be composed safely for a binary output, expose the narrower overwrite contract rather than claim unproved external exclusion.

The final promotion is the operation's commit point. Cancellation observed before entry to the synchronous promotion step prevents publication. Cancellation arriving after successful atomic promotion reports completion, not a fictional rollback. Guard this boundary on the operation owner; a worker's queued completion cannot publish after revocation.

## Registered resource substitutions and final-byte budget

Add a small private ResourceURLSlot table to prepared export output. The resolver/emitter creates slots ONLY for generated resource URL attributes. Each slot references an admitted manifest identity and an occurrence ID. Use a per-operation opaque ASCII marker namespace proven absent from source, title, stylesheet and admitted derived fragments, following the existing export sentinel pattern but with a bounded direct marker lookup. No blind search/replace of `<name>.assets/<hash>` throughout prose/code/raw HTML.

During final assembly, replace exactly registered slots, verify occurrence counts/context and reject unresolved/malformed internal slots before publication. Companion output resolves a slot to a percent-encoded relative URL; self-contained/PDF resolves it to an admitted data URI. Encode URL path components and HTML-escape attribute values separately. Filesystem directory names remain literal. A destination such as `A & B "report".html`, Unicode and `%` must produce correct HTML/CSS links without injection. Never rewrite authored navigation links, raw HTML or code examples just because they resemble managed paths.

Count every emitted resource occurrence, including repeated references to one deduplicated image. Use overflow-checked base64 sizing `4 * ceil(n/3)` plus prefix/MIME and all actual template/style/head/escaped metadata bytes. A final checked UTF-8 sink remains authoritative even after a preliminary size estimate. Abort before a large append/allocation exceeds policy, and check cancellation between bounded chunks. Cache at most one data URI per admitted resource; do not rebuild the entire String per image.

Retain baseline ExportResourceBudget gates (32 MiB source, 512 resources, 32 MiB single resource, 128 MiB aggregate resource payload, 4,096 contributions, 32 MiB derived HTML, 128 MiB prepared body) until the required Release calibration deliberately changes them. Proposed additional final-HTML ceiling: 256 MiB; it is not a measured pass. Give PDF output a separate size admission check before PDFKit reads it. Tests inject tiny policy values only at the trusted internal seam.

Final-artifact bounds do not equal peak memory bounds. Account for prepared body, cached base64, final Data/String conversion required by WebKit, resources, PDF bytes and retained renderer state; record peak memory during calibration. Stream atomically to a staged file where APIs allow it. Do not allocate an additional unbounded String merely to measure it. #117's anchor validation runs before resource amplification and must not introduce an unconditional 8 MiB no-TOC export cap.

## Contained resource reads

Replace resolver path-approval-then-Data reads with the tested #121 descriptor reader, passing Export's policy rather than accidentally inheriting Preview's smaller cap. Preserve safe in-root symlinks and actual MIME/resource identities. Hash the same immutable bytes that are packaged. Ordinary unresolved resources retain the documented warning policy; self-contained/PDF retain fatal required-resource behavior.

Keep mutable cmark state confined to one executor; do not suspend a C tree traversal across actors. Preload bounded references before rendering or invoke the reader's single internal synchronous implementation on the admitted export worker. Either way expensive I/O/encoding does not run on MainActor. Quotas are reserved before asynchronous reads, so concurrent resources cannot each consume the same unreserved remaining budget.

## Asset ownership and crash recovery

Do not adopt a nonempty unknown directory, overwrite an unknown marker, follow an assets-directory symlink or delete by filename pattern. A recognized legacy v1 marker permits cautious reuse but does not prove an inventory. New versioned manifests bind the managed directory to the primary leaf identity/name as well as hashes/types and committed primary digest. A different same-stem output cannot claim it; choose another export name or report the collision. Preserve ambiguous legacy entries and report them instead of inventing their provenance.

Keep a small pending-operation journal with operation ID, prior/desired primary digests, required new assets and OWNED temporary names. Exclusive-create/no-follow all scratch files inside the pinned parent/managed directory. Publication order is journal -> complete verified content-addressed assets -> atomic primary promotion -> committed manifest -> cleanup. Old resources stay until the new primary is known committed. A crash between primary promotion and manifest commit is recovered by comparing the real primary digest against both journal states; an unknown digest disables destructive cleanup.

Second-review correction: hashing a live file and then unlinking its name still has a replacement race. Retirement first atomically renames the candidate to a unique journaled quarantine name in the same pinned directory using no-replace semantics; then opens and verifies the QUARANTINED object's identity/hash against the ownership record. Delete only that verified object. If identity/hash disagrees, restore without replacing an occupied original path; otherwise retain both and report recovery required. Never delete mismatched/unknown bytes, follow a replaced symlink, or overwrite a later writer while restoring. Check every removal boundary, including markers/journals, with the same ownership discipline. Inspect/reuse FileCore's existing conditional-publication approach where it actually applies; do not claim a path precheck repairs this race.

Cleanup failure after successful primary publication is a nonfatal precise warning, not a claim that export wrote nothing. A successful later export reconciles pending operations and removes only verified obsolete owned assets. Unknown/user-modified files remain preserved.

Mode switching policy remains bounded non-destructive retention: self-contained/PDF need not recursively remove the old sibling assets directory. They create no extra companion directories. Subsequent companion exports reconcile the inventory. A trusted aggregate retained-owned-byte/file ceiling includes pending/quarantined entries; exceeding it blocks further companion growth and provides a recovery diagnostic instead of deleting unknown files. Test 100 alternating exports with changed resources and crashes. Different explicitly chosen output basenames are separate user outputs, not a hidden cache.

## PDF execution and cancellation

Show accessible localized preparing/assembling/layout/printing/validation state for the same operation. Keep the existing system print progress panel. Use NSPrintOperation's supported modal callback bridge on the captured origin window, retaining its view/delegate/operation/continuation until actual completion. A callback false value may mean cancel OR failure; do not invent finer semantics without a real signal.

### PDF-PRINT probe — first PDF integration unit

On an interactive supported Mac, run the existing genuine WebKit -> print -> PDFKit fixture through the proposed callback bridge. Measure main-run-loop responsiveness while printing, cancellation behavior, origin closure and terminal callback delivery. The callback API alone does NOT establish nonblocking pagination. Do not dispatch an NSView print operation onto an arbitrary worker. A blocked MainActor watchdog cannot rescue a synchronous main-thread stall; the test driver uses an external process watchdog. If responsiveness is inadequate, stop this adapter unit for a narrow redesign rather than silently weaken the issue.

Before printing, cancellation stops queued preparation/layout and stops WebKit. During printing, invoke only a verified public cancellation route. If cooperative abort is unavailable in the actual phase, retain resources, mark cancellation requested, communicate it truthfully and discard temporary output on completion. Check operation state before validation and immediately before publication. No undocumented abort selector or destruction of a printing view.

Bound output read/validation, confine PDFKit objects and move non-UI work off MainActor where supported. Navigation success/failure, timeout and cancellation share one exact-once terminal function, including stopping the corresponding load. Temporary output uses exclusive creation and is cleaned only by its operation's verified ownership. No empty/unreadable PDF is promoted.

## Units, tests and completion

A. Consume #117 snapshot/origin and #121 reader; add registered URL slots plus final-byte/occurrence/escaping tests. Preserve no-TOC ordinary export and all existing raw-HTML policies.
B. Add per-directory publication admission, primary-bound manifest/journal and quarantine retirement. Inject failures before/after every state transition; test two windows, same-stem .html/.htm, case aliases, external changes, unknown markers, user files, symlink directories and mismatched quarantined objects.
C. PDF-PRINT probe and complete-operation UI/cancellation. Deterministically cancel every phase, especially after print/before promotion and after promotion. Preserve previous output on precommit failure.
D. Real parity/Release calibration and public menu/save-panel/UI/PDF evidence via #88, including #116 math, #117 anchors and E22's actual block-directive outcome.

Boundary corpus: cap-1/cap/cap+1, checked integer overflow, repeated one-image amplification, literal code containing managed resource paths, quoted/percent/Unicode destinations, resource growth/races, mode switching, interrupted manifests and permission/disk-full failures. Real PDFs must preserve searchable/selectable body text, page-crossing code/tables/images/diagrams and print contrast; page count alone is insufficient. Run serial format/lint, affected/full package/app suites and Release app build. Tests requiring GUI must genuinely execute, not remain unconditionally disabled.

The second review fixed unregistered textual replacement, path/attribute escaping, same-stem ownership, unsafe hash-then-unlink cleanup, asynchronous budget oversubscription and ambiguous publication/cancel timing. No runtime, memory, native-print or security PASS is supplied by this document. Every #118 criterion remains required before #115 closes.
