# MostlyText owner checkpoint — 18 October 2026 UTC

The overnight corrections are preserved locally and have passed one combined
non-performance validation pass. They are **not approved for merge or release**.
The tested head is `400d475caaae130cdce1f6de4c6904027e700827`; the complete
review starts at Claude's handed-off `60f779fc`. This checkpoint adds evidence
and documentation only. [Exact commands and results](evidence/overnight-consolidation-2026-10-18/README.md)
remain attached to the tested head.

## What changes for the editor

- Old HTML preview callbacks can no longer settle a different navigation's
  pending load. Queued retries retain their identity during WebKit recovery.
- Stopping or replacing an HTML resource request prevents subsequent delivery
  callbacks, including a stop triggered during response delivery.
- Older preferences missing the status-bar field remain compatible; an explicit
  malformed/null field is rejected instead of treated as a missing Boolean.
- The built app contains the original licence and generated third-party notices.
  Textual's existing Prism payload now has complete byte/component attribution.

Test corrections retire the benchmark window through normal cleanup, isolate
preference domains, and verify idle restoration without assuming a requested
sleep is an exact elapsed interval. The original 150 ms whole-call cleanup limit
is retained. These changes do not establish native CJK input coverage.

## What is verified

The serial package and app-target non-performance gates passed on clean
`400d475c`, as did strict lint/format, Debug and Release app/CLI builds, compliance
regressions, legacy-map checks and ordinary source/artifact compliance.
Independent review found no new material interaction defect in the complete
overnight diff. Both production dependency pools match the unchanged lockfile.

The package run retains two known Neon correctness issues. Two PDF export tests
remain disabled for their documented interactive-session requirement. Native UI
tests were compiled, not executed. AppKit/SwiftUI runtime and Xcode dependency-scan
warnings persist; the app run also reported 101–102 live windows. The teardown
regression does not prove cleanup of every suite's windows. This pass did not
rerun performance suites. The Release artifact
is arm64 with only a linker ad hoc signature, not a signed distribution candidate.

## What still blocks release

- **Preview authority (#121):** a delayed request can still consult a newer root.
  Immutable load ownership, directory grants, race-safe reads, worker/drain limits
  and native hostile-content evidence remain unfinished.
- **Settings/migration (#53):** saves can overwrite unsupported future data;
  only the first unreadable Data generation is backed up, and non-Data
  preservation is missing. A protected-writer contract must precede import.
- **Responsiveness/correctness (#203):** the prior parser result of
  484.814584 ms against 400 ms and editing-assist result of 56.881709 ms against
  50 ms remain unexplained failures. Hosted cleanup overruns also remain
  unresolved. Keep the 8,192 UTF-16 fallback and production pins.
- **Release completion:** seven attribution/source/naming findings, the licence
  screen, final identity/localisation, native interaction/CJK evidence,
  signed-artifact verification and owner acceptance remain open. Manual
  Simplified Pinyin evidence remains Debug-only; automated XCUITest did not prove
  CJK coverage.

## Minimum decisions before preview permission work

1. Choose the file-only asset workflow: offer an explicit folder-selection action
   for sibling assets, or display them only after a folder is deliberately opened.
   A file grant must not silently become authority over its parent directory.
2. Establish the intended shipping OS-access/sandbox configuration so scope
   lifetime and directory-authority tests have an agreed contract.

The recommended next action is owner review of this checkpoint and these two
decisions before preview permission implementation. Any push for fresh hosted CI
requires separate authorization. No push, merge, signing, publication, issue
closure or deletion of unique work occurred in this consolidation.
