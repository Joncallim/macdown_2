# Protect saved settings that this build cannot read

## Owner outcome and scope

Ordinary settings changes must never destroy saved preferences that this build cannot understand. Affected settings remain editable for this session, with a clear warning that those changes are not persisted; readable settings in other domains still save normally. This correction concerns app preferences, not document file saves, and does not change file access or preview permissions.

The approach is a guard in the existing serialized settings writer: inspect the current primary value immediately before writing, and refuse replacement when that present value cannot decode. This preserves future-version, malformed-data and non-Data values without inventing archive rotation, reset consent or a migration importer. The existing first unreadable Data backup remains untouched/compatible; it is never permission to overwrite the primary.

Risk: changes in a protected domain are session-only until a compatible reader or later explicitly authorized recovery resolves it. The Settings window must disclose that limit. UserDefaults does not offer an atomic cross-process compare-and-swap; protection covers the current value observed by this app's serialized writer, not a simultaneous unrelated process write between inspection and set.

Non-goals: resetting/recovering unreadable data, deleting old backups, importing legacy preferences, changing schemas, settings locations, dependency pins, highlighting limits, or claiming #53 complete.

## Baseline and authority

Current master: `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. Source baseline: `a4c48bc72955db21bdd8546c0e97bff051093216` on `review/53-settings-compatibility`. The original bounded decode slice remains recorded in `evidence/settings-53-2026-10-18/`; its probe reproduced future-primary overwrite, loss of a second unreadable generation, and non-Data loss/reporting omissions. The existing writer's comment already promises that newer schema data must not be rewritten, but its implementation violated that promise.

This contract admits the previously deferred setter correction under the owner's instruction to fix load/save and preservation defects. It reconciles the older first-backup-and-replace behavior in the E13 architecture without broad migration work. Read-only independent review accepted the bounded policy and required the cross-process limitation above. The epic standard and release-hardening contract continue to apply.

## Ownership and interfaces

- `AppSettings.UserDefaultsAppSettingsStore` remains the sole writer for its five existing domains. Every setter checks the currently observed primary value; an earlier successful load does not authorize a later overwrite.
- `AppSettingsStoring` exposes the existing read-only `unreadableDomains` diagnostic, with an empty default for compatible alternate stores. Domain getters and setters retain their types.
- `AppSettingsModel` retains live session values, and exposes whether the backing store reports unreadable domains.
- The existing SwiftUI Settings container displays an affected-settings-only session warning. No automatic reset action or new authority is introduced.
- All operations remain MainActor isolated. No new actor, lock, cross-module dependency or I/O path is introduced.

## State and failure behavior

Absent primary -> encode/write as today. Present readable primary -> encode/write as today. Present undecodable primary -> retain it verbatim, retain the first legacy Data backup if one exists (optionally create that existing backup if absent), report the domain, return without changing the primary. Model changes still apply locally; other domains remain independently writable. Reopening/restarting continues to see the original unreadable value and report the protected domain.

A later externally supplied readable value is evaluated afresh and can be written normally. Successive unreadable primary generations are each retained at the primary key; this correction cannot recover generations already lost by prior builds or external writers.

## Implementation and verification slice

First add tests reproducing all five domains across future JSON, malformed bytes and non-Data objects, including an existing backup. Test successive primary generations, reconstructed-store/model warnings, stale model followed by external unreadable replacement, and absent/valid/unrelated-domain controls. Retain the baseline failures before implementation. Update older tests to assert primary preservation, rather than treating a backup alone as proof. Run all AppSettings tests, strict lint/format and app compilation, followed by independent review and exact-candidate integration/hosted gates. Document-save/load corrections remain separate issue-scoped work.

Stop for a need to destroy/reset data, alter file authority, add import semantics, or change the protected persistence contract. No such decision is needed for this bounded guard. #53 stays open for migration/conversion/precedence/idempotence and remaining acceptance work.
