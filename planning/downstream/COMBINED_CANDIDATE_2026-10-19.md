# Candidate for combined release-gate validation

## Owner summary

This candidate combines the reviewed work that keeps file opening, save recovery
and workspace indexing responsive, protects unreadable settings from ordinary
writes, and makes preview callbacks respect their navigation and task lifetime.
It also includes the existing licence-packaging corrections and the reviewed
cleanup/idle-restore regression work. It is a candidate for validation, with
owner review and release gates still open.

The intended editor effects are that delayed reads cannot overwrite newer
edits, saves, document identities or active-window choices; stale workspace
index work cannot publish over a newer root; and reduced highlighting cannot
restore over a newer edit or active marked text. No new dependency version or
fallback-policy change is part of this assembly.

## Assembly and retained provenance

The local branch `review/combined-release-2026-10-19` starts from the reviewed
load/save branch at `71a4dcb54f7b44e397a90b0d94a939d3ecd6bb58`. It merges the
existing integration-fix branch at
`3be9ee2ca680acc5681d22063acf69f5a034dbee`, producing merge
`8be5b59c`. The only automatically merged shared document was the open-issue
acceptance register.

The reviewed timing commit `6d504f625163e1b102e73d1337dff864264d1c6b` is applied
as `decae2b4190a22b4a632fb4fbb2d6e46f5cc7905`. Three test-file conflicts were
resolved after comparing the timing parent against the combined parent. Their
differences were the later style/timeline diagnostics and cleanup-observer
hooks. The resolution retains those diagnostics and the reviewed correction;
all ten timing Swift files match the committed
[evidence manifest](evidence/ci-timing-2026-10-19/source-sha256.txt).

Existing branches, worktrees and dependency experiments are preserved. The
production package lock remains SHA-256
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
Markdown size fallback remains 8,192 UTF-16 units, restoration at or below
6,144 units, and a two-second idle delay. The experimental dependency work is
not incorporated.

At assembly, `integration-final` is
`60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`, and `master` is
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. PR #480 remains draft and unmerged.
No integration/master ref is moved by this local assembly.

## Validation contract

Freeze a clean commit, record its exact head and tree, and run the required
package, app, CLI, lint, format, legacy mapping and compliance validation on that
candidate. Run heavy local builds serially. Record Release app performance and
three planned Release package performance measurements, including failures;
do not rerun until green or weaken a threshold. Verify actual test selection,
not just command exit status. Preserve full logs, process outcomes, dependency
checkout provenance and artifact hashes outside the frozen checkout.

The individual branches' earlier passes remain evidence for their recorded
source only. They do not establish a combined pass. A hosted review must also
record its head, base and synthetic merge revision; a later base change requires
new provenance. A validation-only draft PR into `integration-final` is a review
vehicle, not authorization to merge or release.

## Remaining limits and gates

- Historical hosted styled-run mismatches remain unexplained. The new controlled
  idle tests and separate real-clock style checks must not be presented as proof
  of their cause.
- Earlier parser and editing-assist Release performance failures remain recorded
  until actual combined-candidate measurements establish the current result.
- Seven source/artifact release-compliance findings remain: D2 source location
  and Go/WASM provenance; deeper Mermaid attribution; Tomorrow Light provenance;
  and Graphviz source location, exact source/build records and linked libraries.
- Native Open/Save As, conflict-recovery, external-file, settings-warning/restart,
  preview and accessibility journeys still need their required evidence.
  Package tests and app-target tests do not substitute for these journeys.
- Native Pinyin evidence remains limited to its recorded manual cases. Automated
  XCUITest did not prove CJK coverage. Building UI tests is not a native UI pass.
- Required consecutive full-suite validation, final artifact checks, owner's
  review, signing/notarization and release decisions remain separate gates.
  This work authorizes no signing, notarization, master merge, release, upstream
  submission or deletion of unique work. Issues #53 and #203 remain open until
  their complete criteria are met.
