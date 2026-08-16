> **Title:** [EPIC-17] Distribution & release: identity, Sparkle 2, signing, CLI, macOS 1.0 checklist
> **Labels:** `epic`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** all macOS 1.0 epics + E15/E16 completion

## Owner summary

E17 turns the finished Mac application into a product another person can install, update, understand and trust. It is intentionally the final macOS 1.0 epic: no major feature development should be happening underneath signing, release notes, screenshots or the update channel.

`MacDown 2` is the working development name, not a permanently locked public brand. The final name, bundle identifier strategy, repository home and update-channel identity must be resolved before public release assets are finalised.

## Problem

A working local app is not a release. Users need a signed/notarised build, predictable updates, a coherent first-run experience, understandable documentation, an installable CLI where promised, accurate capability claims and a final identity that will not immediately invalidate the appcast/website/assets.

## Representative user journeys

1. **Clean install:** download the release on a clean macOS 26 machine, pass Gatekeeper, launch without development tooling and create/open/edit/save a document.
2. **Update:** install beta/release N and update to N+1 through Sparkle with signature verification and document/session state preserved.
3. **CLI:** pipe Markdown or open a file from Terminal using the final product command and have it reach the running app predictably.
4. **First run:** understand what the product is, open a representative sample document (including technical-writing examples where useful), and find the main workflows without reading developer documentation.
5. **Trust the claims:** read the README/release notes and find only capabilities that have actually passed their release evidence gates.

## Scope

- Resolve final public product name, bundle-identifier/appcast identity and long-term repository naming/home before release infrastructure becomes public/stable.
- Developer ID signing + notarisation pipeline from CI.
- Sparkle 2.x integration with EdDSA keys and a tested appcast/update path; optional deltas only if they are reliable enough not to complicate the release gate.
- `CLITool` using `swift-argument-parser`: open files, stdin input and `--wait` behaviour as approved by the implementation architecture.
- First-run experience: welcome/sample document, optional MacDown preference/theme import hook if E13/O3 approves it.
- Public parity/capability audit: old MacDown feature marked ported / intentionally dropped / replaced / deferred, plus new MacDown 2 technical-writing capabilities documented accurately.
- Public README/landing/release notes/screenshots that explain the product in human language rather than implementation shorthand.
- macOS 1.0 release checklist rerunning applicable M1-M5 acceptance evidence on the release candidate.
- GitHub Release/appcast publication and migration/announcement note for legacy MacDown users where appropriate.

## Explicit non-goals

- New major product features.
- iPad implementation; post-1.0 iPad work begins only after this release gate passes.
- Mac App Store distribution unless the sandboxing decision is explicitly revisited in a later epic.
- Windows/Linux ports.

## User-visible acceptance criteria

- [ ] Final public name, bundle/update identity and repository/public-link strategy are resolved and consistently applied to release assets.
- [ ] A clean macOS 26 machine installs/launches the signed + notarised universal release build without development exceptions.
- [ ] Two consecutive release-candidate builds update successfully through Sparkle with EdDSA verification.
- [ ] The shipped CLI can open a file and accept piped Markdown using the final product command.
- [ ] First-run/sample content accurately demonstrates the product without relying on developer knowledge.
- [ ] Public parity/capability checklist is reviewed and does not overclaim unverified features/performance.
- [ ] All applicable macOS 1.0 epic acceptance criteria, the feature-complete gate and E15/E16 release evidence are re-verified on the release candidate.
- [ ] README/release notes/installation instructions are understandable without the originating agent/chat context.
- [ ] macOS 1.0 is published with a working update channel.

## Release placement

E17 is the final macOS 1.0 epic. Its completion is the boundary after which iPad implementation may be planned/started.

## Architecture gate

E17 must satisfy `planning/EPIC_STANDARD.md` before implementation begins. Its current-master architecture pass must verify final identity decisions, signing/notarisation credentials/process, Sparkle topology, CLI ↔ app communication and clean-machine verification rather than assuming the original placeholder bundle/name choices remain correct.
