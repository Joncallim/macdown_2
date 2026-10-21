# Preserve unreadable saved preferences

Ordinary preference changes now leave every observed unreadable primary value intact. This includes future-version JSON, malformed Data, non-Data values, and a second unreadable generation after an existing backup. Edits still take effect in the running session; the Settings window explains that affected settings will not persist. Readable domains save independently. This is a settings-preservation correction, not a document-save fix or completion of #53.

## Provenance and evidence

Base: `a4c48bc72955db21bdd8546c0e97bff051093216` on `review/53-settings-compatibility`. The source hashes in `final-validation.json` identify the tested uncommitted implementation; the enclosing commit seals those files and this evidence. Production dependency lock remains SHA-256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`. No highlighting cutoff or dependency changed.

- Unchanged production writer plus the new regressions produced 77 failed expectations, including loss of the original primary values. An earlier test-isolation compile error is retained separately and is not the negative control.
- Final serial `swift test --no-parallel --force-resolved-versions --filter AppSettingsTests` passed, including all five domains, four unreadable value shapes, successive generations, stale models, readable replacement and unrelated-domain controls. Strict changed-file SwiftLint and SwiftFormat passed.
- The unsigned Release app built successfully with XcodeGen and the committed resolved versions. `app-build-commands.json` and `release-build-source.json` identify that build. The only compiler-source change after this build was correction of the store's schema comment; final package tests compiled that correction. Xcode's metadata extractor reported its standard missing-AppIntents dependency notice; there were no Swift compiler warnings. The package lock and generated workspace lock still match.
- Independent source review found no material runtime defect. Its two stale documentation findings were corrected before final validation. The reviewer ran no builds or tests.

Raw logs are retained at `/Users/jonathanlim/GitHub/_cleanup-archive/settings-protection-a4c48bc7-2026-10-19`; their hashes are in `raw-log-hashes.json`. One final-check launch was blocked by SwiftPM's nested sandbox before tests ran; the same check then ran outside that nested sandbox. This was an environment failure, not a failing assertion.

## Limits and next gate

Tests reconstruct stores/models in the same process. They do not execute an app restart or inspect native warning layout/accessibility. UserDefaults has no cross-process compare-and-swap; the guard protects the value observed at this writer's boundary. Existing lost values cannot be reconstructed. Explicit recovery, legacy conversions, precedence, consent, idempotence and E23 destinations remain open under #53. The actual combined candidate still needs hosted CI, final Release performance evidence and owner acceptance.

The binding bounded contract is [SETTINGS_WRITE_PROTECTION_2026-10-19.md](../../SETTINGS_WRITE_PROTECTION_2026-10-19.md).
