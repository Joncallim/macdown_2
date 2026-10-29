# Save As link correction and signed acceptance, 2026-10-29

Save As now routes retained relative preview links against the new document folder, while explicitly absolute links keep their authored destination. The final signed native run verified both behaviors without losing the established source viewport. This is a bounded #519/#121 checkpoint, **not issue closure or complete release acceptance**. A separate automatic-appearance-transition viewport observation and historical fixture-readiness failure remain documented.

## What failed and changed

The exact published candidate `9e2940353b66bfa8fd6951e144201ac85e394cca` built and verified as Developer ID with hardened runtime and no entitlements/App Sandbox. Its first signed repeat preserved original and link-rich Save As geometry and revoked image grants correctly. However, clicking a visible relative link after A/links-bounded.md became B/signed-final-links.md still opened **A/related.md**, whose distinct heading confirmed the stale target. See first-native-link-failure.json and the task's native accessibility/screenshot transcript. The failing executable is retained locally, SHA-256 `e83d15a17f2d77a2546eee150fb63d9a553639c3c14be3e2a9fc09c44b21d014`.

A real-parser regression reproduces one concrete failure path: a URL retains lexical `related.md` and base A, so its inherited `file` scheme fooled PreviewLinkResolver into treating it as an explicit absolute target. It ignored current base B. The new regression failed with five assertions before the correction; that first failure is retained.

The resolver now checks the lexical scheme in `url.relativeString`, resolves relative references against the current document, and returns a self-contained URL before action routing strips fragments/query. It never infers relative intent by an absolute URL's folder prefix. Authored absolute file/web destinations remain unchanged; the existing scheme/extension allowlist, same-document anchor rule and executable reveal-only policy are unchanged. No resource loader, grant, quota, attachment identity or dependency changed. The precise Textual state layer retaining the native URL was not isolated, and no broader rendering-cache claim is made.

## Validation of the corrected local source

Source is `9e294035` plus the two-file correction recorded by source.json's patch hash. The signed executable SHA-256 is `e0d65c638e4826fade7fc4f89d446dcba98ec009f29bd0fb185f170675553838`. Documentation added afterward does not change that built source. Independent read-only review found no material safety blocker.

| Check | Result |
|---|---|
| Real-parser/cached-link regressions before correction | RED: two tests, five assertion failures |
| Link action, resolver and markup cache tests after correction | 21 tests / three suites passed |
| Complete locked package suite, serial | 2821 tests / 384 suites passed in 261.575 s; two recorded Neon known issues |
| Complete app-target suite, serial | 522 tests / 106 suites passed in 72.910 s |
| Strict changed-file lint/format, source and built-artifact compliance | passed |
| Optimized Release build, signed app and preserved-copy verification | passed; Developer ID, hardened runtime, empty entitlements, no App Sandbox |
| Corrected signed native Save As, relative/absolute links and grants | bounded checks passed below |

Build and execution used locked dependencies, automatic resolution disabled, arm64 native execution and private test homes/session/recovery directories. The app artifact is universal; native execution here establishes arm64 only. Local toolchain: Xcode 26.6 / Swift 6.3.3, macOS 26.5.1 (25F80). Existing `ISSUE117_NATIVE_ACCEPTANCE` startup was used. No keychain prompt was observed or security setting changed. Developer ID verification is not notarization/Gatekeeper or normal shipping-startup proof.

## Actual final native checks

- **Link-rich document:** 120 paragraphs with a relative link in every paragraph, 11483 UTF-8 bytes. After opening/closing A's target, the actual pre-Save-As source scrollbar was **0.5025325333125535**, caret **Ln 123, Col 27**. Native Save As to B/corrected-final-links.md retained both exactly. A visible link opened **B/related.md**, showing `RELATED_TARGET_FROM_B`. The old image grant became unavailable; an explicit fresh B grant loaded B's blue near-end image. The earlier source-scroll value before the auxiliary A navigation was different because native tab geometry changed; it is not substituted for the actual immediately preceding Save As control.
- **Absolute destination control:** an explicitly authored file URL to A/related.md was saved as B/corrected-absolute.md. Clicking it still opened **A/related.md**, showing `RELATED_TARGET_FROM_A`.
- **Original document under stable Dark appearance:** the same 35307-byte, 500-paragraph corpus from the prior base comparison was positioned at paragraph480, caret **Ln 991, Col 19**, source scrollbar **0.9690132433314412**. A one-character insert and deletion, native Save As to B/corrected-final-story.md, and fresh B grant all retained that source scrollbar. GREEN retired to alt/unavailable after Save As; the fresh B grant loaded BLUE. Preview paragraph shifts caused by retiring/reloading image height are recorded separately from global source collapse; no pixel-identical preview claim is made.
- All three Save As results were byte-identical to their A sources. The private app exited zero without a resource/deadline guard firing. Real session SHA-256, recovery entry count/directory mtime and window-frame default hash matched before/after. These receipts contain no real document content.

## Open appearance observation

During an earlier original-document edit check in the final run, one batched computer-control call timed out after 30.886 s and reset its control kernel. A fresh read found source scrollbar **0.002986173323055289** (previously **0.9400890296325453**) while the caret remained Ln991/Col19 and the original source bytes had been restored. The screen had changed from Light to Dark. Read-only OS checks reported automatic appearance switching enabled, Dark active and global-preferences mtime **2026-10-29 19:00:19.680614 +08:00**, coinciding with the event. This is a confound, not proof of cause; neither the exact action phase nor attribution to #519 is established. See appearance-transition-observation.json. No system appearance setting was changed by this work.

The subsequent stable-Dark insert/delete/Save As checks above are separate positive controls, not an erasure or passing reclassification of that observation. Automatic appearance-transition viewport acceptance remains open. The earlier 500-paragraph link-heavy near-end source-reveal concern is also unchanged/unattributed; the bounded 120-paragraph check does not claim to resolve it.

## Retained package discrepancy and remaining gates

See [readiness-investigation.md](readiness-investigation.md). The original #519 complete-package run failed the held-group fixture's unchanged one-second readiness assertion. The same case passed once in isolation (0.424 s), in hosted CI (0.149 s), and in the necessary full validation of this newly corrected source (0.553 s). Original child stderr/startup timestamps were not recorded, so scheduling versus tool failure cannot be proved. No readiness deadline, ownership assertion or TextFilters source/test changed. The first failure remains retained; current green results do not establish its cause.

Hosted CI 40848059633 and Compliance 40848059733 passed for the **older published 9e294035** (GitHub merge 9299aca into ancestor base7b8b4055). They do not validate this new local correction. The current instruction prohibits pushing #519, so updated hosted validation remains pending publication; no push, PR update, formal approval, ready mark or merge was performed for this correction.

Normal shipping startup, notarization/Gatekeeper, complete keyboard/VoiceOver, full hostile/race/navigation coverage, long-session resource endurance and other existing #121/#115 gates remain open. No acceptance requirement is waived by these bounded results.

Local full artifacts: `/tmp/mostlytext-519-saveas-20261029`. The prior failed signed run is under `native-repeat-9e`; the final corrected binary, private fixtures and lifecycle receipts are under `native-retained-link-fixed`. Full package/app logs, signed build log and app xcresult remain there. The small committed logs and artifact-checksums.json preserve relevant results and hashes; large binaries/result bundles are not committed. Native visual/accessibility observations are in this task's computer-use transcript.
