# macOS 1.0 execution and authorization sequence

Status: proposed cross-epic contract amendment in the recovery/readiness PR #147, 26 September 2026. It becomes repository authority when that documentation PR is adopted; no release is authorized by its existence. It clarifies RELEASE_HARDENING.md sections 7–8 without weakening issue acceptance, artifact identity, security, fidelity or language requirements.

## Why the old shorthand must be expanded

The historical shorthand `E22 -> identity -> E23 -> #115 -> final E16 -> E17` mixed implementation milestones with final issue closure. #115's full matrix already requires final E16 plus exact signed-candidate UI/VoiceOver/export/Quick Look evidence, while E17 prohibits public production approval before #115 closes. Treating all arrows as whole-issue closure creates a cycle.

Use three milestones. Implementation dependencies are between tested units, not arbitrary closed issue numbers. Required final evidence still determines when each issue can close.

## S — Software and UI stabilized

Complete E22 under its existing implementation plan, final technical identity intake and E23 capability work. Implement all required carried-forward product corrections. Complete E17's application-side bootstrap, settings/namespace/legacy migration, CLI, updater integration and user-visible messages BEFORE this milestone. All such changes include their own catalogs/tests; E16 is not a dumping ground for new English-only screens.

S requires an exact source/identity/UI baseline, applicable engineering verification and no known required unimplemented behavior hidden as a manual task. Final Mac-only evidence and native-language review may still be outstanding and remain explicitly recorded. #115 stays OPEN. Architecture-level readiness, package CI or an issue's implementation subset do not by themselves establish S.

The software-stabilization references in older issue bodies are read as S, not final #115 closure. Do not rewrite historical result records or claim old evidence passed. Do not modify active E22 work merely to change this scheduling vocabulary.

## V — Final localization and private exact-artifact verification

After S, E16 performs the final actual resource/string audit, translation/native-review/plural/layout work and freezes the exact source/translation/UI baseline. E17 prepares private unapproved signed/notarized artifacts and controlled N -> N+1 update rehearsals. Signing/notarization here is for evidence preparation, not public publication or production approval.

Execute all required final UI, VoiceOver, native-modal, file/recovery, HTML/PDF, math/diagram, theme, Finder/Quick Look, clean installation, stateful migration and signed-update checks on the actual candidate binary. Verify executable paths and identities, not a different Debug build with the same name. Missing credentials, permissions, suitable Mac or native review are BLOCKED/NOT_RUN, never assumed passes. #115 remains open until every required obligation is FIXED/PROVED with valid evidence, or rejected only where the original optional-feature contract allowed it.

A failed check may require code/UI/string changes. Return affected work to S/E16 as necessary, create a newly identified candidate and rerun affected proof plus the final critical regression. There is no formal dependency from S to future V completion: this is an explicit feedback loop after a failed test, not a circular prerequisite that prevents work beginning.

Before #115 closes, retain the exact final E16 record and all artifact evidence. Individual implementation issues close only after their complete own acceptance is evidenced, including any V-only obligations. A tested prerequisite unit can be consumed while its umbrella issue awaits final evidence.

## P — Separately authorized public promotion

Public production RC/release authorization is forbidden while #115 is open or required final E16/artifact evidence is missing. Once the full gate passes and #115 closes, obtain the actual owner/release-process authorization. This documentation task, a green workflow, an architecture review or a private signature is not that authorization.

Promote the SAME bytes that passed V. Do not rebuild, re-sign, rewrite Info.plist, alter entitlements, replace resources or swap the artifact after approval. Upload immutable versioned assets/notes first, verify downloaded bytes/signatures, and publish the stable appcast last. Retain the previous known-good release. Any changed identity/content invalidates affected proof and requires reverification before promotion.

## Preserved release requirements

Zero release-relevant P0/P1/P2; only explicitly accepted cosmetic P3. No required unverified/blocked/accepted-debt row. Genuine native tests are not substituted by build-for-testing. No source normalization or loss of authoritative preferences/session/recovery/themes/snippets. Offline rendering and exact resource grants remain mandatory. The legacy/development migration and two signed-build update rehearsal are still required. The final human/language/artwork checks remain as actually approved by their owning records; a real waiver must be named as a waiver, not invented by an implementation agent.

## Adoption and ongoing use

RELEASE_HARDENING.md links this sequence as its current execution interpretation. The revised #17/#18/#115 hand-offs refer here. At adoption, add short cross-links to relevant issue discussions rather than replacing their product acceptance text. Older statements that final localization waits for all of #115 to close are superseded only as sequencing, not as a waiver of any criterion.

Use planning/downstream/readiness.json for unit dependencies and named unrun probes. It is a planning artifact, not the future runtime release-evidence manifest and not an executable release approval.
