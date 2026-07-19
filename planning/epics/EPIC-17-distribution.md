> **Title:** [EPIC-17] Distribution & release: Sparkle 2, signing, CLI, 1.0 checklist
> **Labels:** `epic`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** all previous epics

## Context

New product (D5): new identity, new update channel, new CLI. Unsandboxed
direct distribution (D7). Nothing carries over from Sparkle 1.x/DSA.

## Scope

- Developer ID signing + notarization pipeline (GitHub Actions release job)
- Sparkle 2.x integration: EdDSA key generation, appcast hosting (GitHub
  Releases is fine), delta updates optional
- `CLITool`: swift-argument-parser port of macdown-cmd (`<product> file.md`,
  stdin pipe support, `--wait` flag new) — talk to the app via the same
  shared-suite mechanism or XPC
- First-run experience: welcome window, sample document, optional MacDown
  theme/pref import hook (from E13/O3)
- Parity audit: feature checklist vs. old MacDown — each item marked
  ported / intentionally dropped / moved to v1.x (published in the repo)
- 1.0: GitHub Release, appcast live, README + landing page, announcement
  issue on the old fork

## Deliverables

1. Signed + notarized universal binary from CI
2. Working Sparkle 2 update between two consecutive beta builds (tested)
3. CLI binary shipped inside the app bundle + install helper
4. Published parity checklist + release notes

## Acceptance criteria

- [ ] Clean-machine install (Gatekeeper pass) on macOS 26
- [ ] Beta N → Beta N+1 auto-updates via Sparkle (EdDSA verified)
- [ ] `echo "# hi" | <product>` opens a rendered tab
- [ ] Parity checklist reviewed and public
- [ ] All M1–M5 acceptance criteria re-verified on the release build

## Out of scope

Mac App Store (requires sandboxing — revisit with D7 later); Windows/Linux.

## Notes

Decide product name/repo home (O1/O2) before this epic starts; the appcast
URL and signing identity depend on it.
