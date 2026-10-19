# Document load and save responsiveness corrections

## Automatic encoding opens

A BOM-less UTF-16 file's detection read and scan now run away from the UI actor. Automatic retry retains its original open-request identity, so finishing an older open cannot steal focus from a newer one. A newer successful open of the same URL is reused even if the old automatic detector cannot identify its encoding. Explicit encoding and conservative no-guess behavior remain unchanged.

Baseline is `91e62f8f`, on `review/183-load-save-responsiveness`. `encoding-reviewed-final.json` records the exact final source hashes; the enclosing commit seals that implementation. Tests hold the real detector while a newer open completes, cover both successful UTF-8-with-NUL and failed-UTF-8 paths, and verify correct text, encoding, focus and duplicate admission. The original retry-generation reset was restored as a controlled mutation: both focus assertions failed. That is a mutation control, not an untouched-production timing measurement. Independent review found the additional nil-detection stale-error path, and its new Latin-1 regression failed before correction. Both negative controls remain retained.

The final serial locked-dependency encoding/core tests passed, without compiler warnings. Strict changed-file lint and format passed. Opening methods moved into `TabStore+Opening.swift` to meet the repository's file-length rule. One existing unnecessary `try` in an encoding fixture was removed after compilation reported it. Independent review found no remaining production admission defect and required held readers to be joined before throwing fixture exits; that correction is included in the final validation.

Execution disconnected during the first test launch; it left an empty log and no result. A process check found no surviving compiler/test process before validation resumed. No interrupted command is counted as passed. Raw evidence is retained under `/Users/jonathanlim/GitHub/_cleanup-archive/load-save-91e62f8f-2026-10-19`, with recorded hashes.

This is deterministic concurrency and correctness evidence. It does not establish end-to-end document-open latency, remove repeated reads, or finish the workspace-index/save-conflict slices. Actual combined Release performance, hosted CI, native paths and owner review remain open. See the [bounded contract](../../LOAD_SAVE_RESPONSIVENESS_2026-10-19.md).
