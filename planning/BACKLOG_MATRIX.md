# Open-backlog working matrix

Snapshot 2026-10-09, master after #388. Status words: **open** (not started), **partial** (merged work, acceptance not met), **gated** (needs native/human evidence or an owner decision). Release sequence and shared-contract ownership are defined in the architecture draft (#147); this file only tracks remaining requirement, owner and next action.

| Issue | Remaining requirement | Owner / depends on | Required evidence | Next action |
| --- | --- | --- | --- | --- |
| #183 | Pre-1.0 audit findings F01–F03, F08, F10, F23 extensions; tenth-review items | Self (code in `Workspace`, `ExternalFileController`, `EditorCore`) | Deterministic regression per finding, full gates | Merged #374–#384 cover Find freshness, Save As lineage, bind retry, frame height, bare-CR, IME guards. Open: gated Save-As-continuation and tab-switch/disposal F01 tests; Markdown-assist Tab bare-CR path. Reconcile the handoff comment |
| #159 | Typed readiness, async fixture ownership, ESRCH vs indeterminate termination checks | Self; independent | Lifecycle suite stable under load | #385 merged (readiness + cleanup). Do ESRCH/indeterminate helper, then close |
| #215 | Hermetic descriptor | Self | Suite stable | Closed by #386 |
| #163 | Deterministic parse interleaving; busy-state ownership | Self | Failing-then-passing regression | Closed by #387 |
| #203 | Markdown block reparse ≈ full parse at 1 MB | Self; grammar (`Packages/TreeSitterMarkdown`) | Release `HighlightPerformanceTests` showing ≤ 50 ms or an accepted, documented budget change by the owner | #388 corrected the benchmark and added a reuse control; investigate scanner state serialisation |
| #155 | WebKit lifecycle hang root cause | Self; needs native repro on a loaded session | Native WebKit run, not a model | Instrument teardown ordering; keep distinct from #159 |
| #173 | Already-open document reveal lifecycle | Self; native activation | Native UI proof | Reproduce under XCUITest |
| #88 | Remaining `MacDown2UITests` gaps | Self; native | Native UITest runs | Triage list, execute in dependency order |
| #121 | HTML preview request/root and resource-read races; shared resource access/lifetime contract | Self; blocks #113, #117, #118 | Native WebKit + unit seams | Define the contract once, then implement |
| #117 | Anchors, contributed IDs, immutable export snapshots, SVG occurrence namespaces | Self; after #121 | Unit + export parity | Design after #121 |
| #116 | Exact source/container-decoded math, reference-link identity, mapped diagnostic coordinates | Self; after #117 | Unit + VoiceOver (human) | Resolve reference identity and coordinate maps first |
| #113 | Themes, Quick Look, presentation | Self; after #121/#117 | Native Quick Look | Queued |
| #118 | Export integration and publication safety | Self; after #117 | Export parity, security review | Queued |
| #53 | Compatible settings decoding before migration/import writers | Self | Unit | Queued before any migration writer |
| #79 | Theme-coherent Mermaid/D2/Graphviz | Self; after #113 | Native render | Queued |
| #119 | EPIC-18 manual and performance evidence | Gated (manual/perf runs) | Recorded evidence | Prepare run sheets |
| #120 | #57 Open/Save UI and latency carry-forwards | Self; native | Native UITest + perf | Queued |
| #112 | Editor essentials epic | Aggregates #203 and slice work | All slices accepted | Track via children |
| #17 | Final E16 localisation | Gated: after all strings final | Catalog audit | Late in sequence |
| #18 | Distribution and release (signing, Sparkle, CLI) | Gated: owner authority for signing/publication | Signed artifacts | Not started; needs owner approval for credential-sensitive steps |
| #148 | Licensing, provenance, exact-artifact compliance | Gated: source-archive publication needs owner approval | Compliance gate on final artifact | Archive plan drafted in #147; publication not requested |
| #158 | Identity and final repository cutover | Gated: owner-authorised, last | Cutover checklist | Do not start |
| #115 | Gate: all carried-forward debt eliminated | Aggregates the above | Software/native verification pass | Closes last before cutover |

Rejected-finding ledger (brief): pass-9 Preview `\r` suspicion (markdownLines already splits CRLF); settings-compat edge removal (edges kept, direct software edge added); recovery fence/retired-epoch edge cases (recorded limitations, not defects).
