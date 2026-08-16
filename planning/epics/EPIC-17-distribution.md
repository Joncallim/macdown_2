> **Title:** [EPIC-17] Distribution & release: migration, Sparkle 2, signing, CLI, macOS 1.0 checklist
> **Labels:** `epic`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** frozen identity + E15/E16 completion + all macOS 1.0 feature work

## Owner summary

E17 turns the finished Mac application into a product another person can install, update, understand and trust. It is intentionally the final macOS 1.0 epic: no major feature development or new in-app experience should be happening underneath signing, release notes, screenshots or the update channel.

The public product identity is **already frozen before E15** by the feature-complete gate. E17 applies, migrates and verifies that identity; it does not decide the brand at the end of the release cycle.

The release must also survive the thing clean-install tests miss: upgrading a real development/beta installation containing settings, sessions, recent roots and recovery data into the final identity/update channel without silently losing user state.

## Problem

A working local app is not a release. Users need a signed/notarised build, predictable updates, a coherent already-localised first-run experience, understandable documentation, an installable CLI where promised, accurate capability claims and safe migration from development/beta identifiers.

## Representative user journeys

1. **Clean install:** download the release on a clean macOS 26 machine, pass Gatekeeper, launch without development tooling and create/open/edit/save a document.
2. **Stateful update:** start from a prior development/beta install with representative settings/session/recovery data, update/migrate to the release candidate, and retain authoritative user state.
3. **Sparkle update:** install release candidate N and update to N+1 through Sparkle with signature verification and document/session state preserved.
4. **CLI:** pipe Markdown or open a file from Terminal using the final product command and have it reach the running app predictably.
5. **First run:** use the E15-defined/E16-localised welcome/sample flow without encountering English-only UI invented during distribution work.
6. **Trust the claims:** read the README/release notes and find only capabilities that have actual release evidence.

## Preconditions

- Final public name, bundle/update identity strategy, CLI public name where affected, repository/public-link strategy and migration namespaces were frozen by the feature-complete gate.
- E15 finalised app icon, first-run/onboarding UI and release-blocking whole-app polish.
- E16 completed localisation/string freeze.
- The release-evidence ledger has no P0/P1 and clearly records any accepted P2.

## Scope

- Apply the already-approved final public product name, bundle/update identity and repository/public-link strategy consistently to release infrastructure/assets.
- Implement and test migration from working development identifiers/namespaces where required: Application Support, defaults/preferences, session data, recent roots/bookmarks/URLs, untitled recovery buffers and other authoritative state.
- Disposable caches may be discarded/rebuilt deliberately; authored recovery/session data must not disappear silently.
- Identity migration must be idempotent enough that relaunch/retry cannot repeatedly move/delete valid state or lose a recovery branch after a partial failure.
- Developer ID signing + notarisation pipeline from CI.
- Sparkle 2.x integration with EdDSA keys and a tested appcast/update path; optional deltas only if they are reliable enough not to complicate the release gate.
- `CLITool` using `swift-argument-parser`: open files, stdin input and `--wait` behaviour as approved by the implementation architecture.
- Package and verify the E15 first-run/sample experience; do not redesign it in E17.
- Public parity/capability audit: old MacDown feature marked ported / intentionally dropped / replaced / deferred, plus new technical-writing capabilities documented accurately.
- Public README/landing/release notes/screenshots that explain the product in human language rather than implementation shorthand.
- macOS 1.0 release checklist rerunning applicable acceptance evidence on the exact release candidate.
- GitHub Release/appcast publication and migration/announcement note for legacy MacDown users where appropriate.

## String-freeze constraint

E17 must not introduce a new user-facing app screen or new in-app user-facing string after E16 without updating the String Catalog and rerunning the affected localisation/pseudo-localisation checks. Release notes/website copy are outside this in-app freeze.

## Required stateful migration rehearsal

At least one release rehearsal begins with a previously installed development/beta build containing representative:

- settings/preferences;
- recent roots/workspace state;
- restored windows/tabs/session data;
- bookmarks/URLs where applicable;
- untitled recovery buffers;
- existing caches;
- old development-name Application Support/defaults namespaces if they differ from the final identity.

After install/update/migration to the release candidate, authoritative state must remain available or be deliberately migrated. Caches may rebuild. The test must include relaunch and at least one repeated migration/startup attempt to prove idempotent behaviour.

## Explicit non-goals

- Deciding the public brand/name in E17.
- New major product features.
- New first-run/onboarding UI after localisation.
- iPad implementation; post-1.0 iPad work begins only after this release gate passes.
- Mac App Store distribution unless the sandboxing decision is explicitly revisited later.
- Windows/Linux ports.

## User-visible acceptance criteria

- [ ] Frozen public name, bundle/update identity and repository/public-link strategy are consistently applied to release assets/infrastructure.
- [ ] A clean macOS 26 machine installs/launches the signed + notarised universal release build without development exceptions.
- [ ] A stateful development/beta installation migrates to the release candidate without losing authoritative settings/session/recent-root/recovery state.
- [ ] Identity/state migration is repeatable/idempotent enough that relaunch/retry does not duplicate or silently discard valid state.
- [ ] Two consecutive release-candidate builds update successfully through Sparkle with EdDSA verification while preserving representative user state.
- [ ] The shipped CLI can open a file and accept piped Markdown using the final product command.
- [ ] First-run/sample content is the E15/E16-approved flow and accurately demonstrates the product without relying on developer knowledge.
- [ ] No unlocalised in-app release UI is introduced after E16 string freeze.
- [ ] Public parity/capability checklist is reviewed and does not overclaim unverified features/performance.
- [ ] The exact release candidate re-verifies applicable macOS 1.0 acceptance evidence and has no unresolved P0/P1.
- [ ] README/release notes/installation/migration instructions are understandable without the originating agent/chat context.
- [ ] macOS 1.0 is published with a working update channel.

## Release placement

E17 is the final macOS 1.0 epic. Its completion is the boundary after which iPad implementation may be planned/started.

## Architecture gate

E17 must satisfy `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. Its current-master architecture pass must verify frozen identity inputs, state/namespace migration, signing/notarisation credentials/process, Sparkle topology, CLI ↔ app communication, string-freeze compliance and clean-machine/stateful-update verification.
