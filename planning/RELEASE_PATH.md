# MostlyText 1.0 release path

**Owner summary.** This is the coordination map from today's `master` to a
public, signed and downloadable MostlyText 1.0. It adds no scope. Every item
below already has an owning issue or epic, and those issues remain the
binding contracts. This page shows:
- the order the work must happen in;
- what can start now;
- which steps need a Mac rather than a cloud session;
- which decisions only the owner can make.

The brand identity is now frozen for 1.0: design gates 1 and 2 are closed,
gate 3 was waived (D-026) and gate 4 is deferred (D-031). Brand decisions are
therefore off the critical path. What remains is:
- finishing E22;
- the identity cutover (#158);
- E23;
- the debt and licensing gates (#115, #148);
- the final string freeze (E16);
- distribution (E17).

The main risks are credentials and hosting that don't exist yet: an Apple
Developer ID, a Sparkle signing key, and website and archive hosting. Leaving
them to the end would stall E17. Non-goals: this page doesn't reorder the
epics, relax any gate, or authorise publication.

Terms used here:
- **RC:** release candidate, the exact build intended for publication.
- **Notarisation:** Apple's automated malware scan. It is required before
  Gatekeeper, macOS's download-verification check, lets a Developer ID app
  open without warnings.
- **Sparkle:** the open-source macOS update framework.
- **Appcast:** Sparkle's update feed.
- **EdDSA:** the signature scheme Sparkle uses to verify updates.
- **SBOM:** software bill of materials, a machine-readable list of every
  component shipped.

Status as of 2026-09-27, after #136 merged (`d13f3d1`).

## 1. Critical path

This is the hard order set by #158, `planning/RELEASE_HARDENING.md` and E17
(#18):

```text
E22 (#112, in progress) ─▶ identity cutover (#158) ─▶ E23 (#113)
    ─▶ #115 debt gate (with #116–#121, #88, #79, #53)
    ─▶ final E16 string freeze (#17) ─▶ E17 distribution (#18) ─▶ public 1.0

Runs alongside, and must pass before #115 closes and before E17 promotes:
    #148 licensing/provenance (LC-01–LC-10)
Can be prepared early, used at E17:
    Apple Developer ID + notarisation credentials, Sparkle EdDSA key,
    website/archive hosting
```

E22 is being delivered slice by slice by its own session. Slices 1–6b have
landed; 6c (recent files), 7 (folder search/replace), 8 and 9 remain. Nothing
on this page interrupts that work.

## 2. Workstreams

| Workstream | Owning issue | Can start now? | Where | Next concrete step |
|---|---|---|---|---|
| Brand identity | D-001–D-031 (`design/`) | **Done for 1.0** | — | None. Rename the Figma file title from "(Slant 12°)" in the Figma UI (D-029) |
| Branding cutover (repository, README, public copy) | #158 | Record only. #158 runs after E22 | Cloud | Draft the §1 identity-freeze record (name, links, repository name, CLI, bundle/update strategy) as a proposal for the owner decisions in §4, then execute once E22 closes |
| App-icon integration | E23 (#113); inputs from #158 | No. E23 follows #158 | Cloud edits; **Mac** to verify | Move `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon` into the app **next to** `Assets.xcassets`, not inside it, and remove `AppIcon.appiconset` and the placeholder script. See that folder's README (D-028). Verify in a Release build in the Dock and Finder, light and dark |
| Bundle identity and versioning | Strategy: #158. Migration: #18 | Proposal now | Cloud | Today the app is `com.joncallim.MacDown2`, `0.1.0 (1)`, and the CLI is `macdown2`. Propose the final bundle ID, CLI name and version scheme (§4). E17 owns the migration from the development namespaces |
| Licensing and notices | #148 (LC-01–LC-10) | **Yes.** LC-02–LC-07 are identity-neutral | Cloud | Start with LC-05 (pin SwiftTreeSitter to an immutable revision) and LC-04 (TreeSitterMarkdown provenance), then the SBOM and notice generator (LC-01/07). LC-08's About → Licences UI must land before the final E16 freeze |
| Trademark | D-031 | Nothing for 1.0 | — | Ship with no "®" and no clearance claim. Revisit if MostlyText gains material adoption, revenue or sponsorship, press recognition, third-party brand use or other brand value |
| Signing and notarisation | E17 (#18) | **Groundwork, yes** | **Mac** | Owner confirms Apple Developer Program membership. A Mac session runs a non-publishing Developer ID and notarisation dry run on current `master` (§3) to find hardened-runtime and entitlement problems early. No entitlements file exists yet, and the hardened runtime isn't enabled |
| Packaging and downloads | E17 (#18) | Decisions only | Cloud decides; Mac builds | Choose the download format and host (§4). The Sparkle EdDSA key is generated once, on a Mac, and stored in the owner's keychain or password manager, never in the repository |
| Website and deployment | E17 (#18); LC-09 (#148) | Yes, as a draft | Cloud | Nothing exists in the repository yet. Decide the host and repository location (§4), then build a static site at `mostlytext.app` covering the download, appcast, `/opensource` compliance archive (LC-09) and privacy statement. Public copy claims only capabilities with release evidence |
| Clean-install and update verification | E17 (#18); #115 | No. Needs the exact RC | **Mac** | On the signed, notarised RC: clean install on macOS 26 in a fresh user account or VM, Gatekeeper, first run, CLI, Sparkle N→N+1, migration from development state, legacy MacDown preference import (#53) |

## 3. Cloud and Mac split

Cloud sessions (Linux, no Xcode) own GitHub, planning, issue coordination,
documentation, CI configuration, website source, the licence and SBOM
tooling, Figma, and every source change that ordinary CI can check.

A Mac session is used only for what cannot run anywhere else:
- Developer ID certificates and keychain work;
- signing, notarisation and stapling;
- final Release builds;
- Gatekeeper and install tests;
- live Dock, Finder and Quick Look checks;
- executed XCUITests (#88).

No Mac environment is registered for cloud sessions. Mac work therefore runs
in the owner's local Claude Code on their own Mac, from a tightly scoped
brief. Each Mac brief must:

1. Name the exact commit or tag it works from, and the evidence it must
   return.
2. **Never publish.** No GitHub Release, appcast upload, website deploy or
   push to `master`. Evidence and small fixes go on a branch through a PR.
3. **Never commit credentials.** No certificates, `.p8`/`.p12` files, app
   passwords, notarytool profiles or Sparkle private keys, whether in the
   repository, in logs or in screenshots. Record only certificate names and
   Team ID, notarisation submission IDs and statuses, and hashes.
4. Stop and report when it hits a missing credential, a hardened-runtime
   problem that needs an architecture change, or anything that would change
   product behaviour.
5. Store evidence under `planning/evidence/YYYY-MM-DD/` (release; the folder
   doesn't exist yet and is created by the first Mac run) or
   `design/evidence/YYYY-MM-DD/` (visual), following
   `planning/RELEASE_EVIDENCE.md`'s rule that unavailable means `unverified`,
   never passed.

The first Mac brief is the signing and notarisation dry run described in
the table. It is queued for the owner to start when their Developer ID is
ready.

## 4. Owner decisions needed

These block the cutover or E17. Each has a recommendation, but the owner
decides.

1. **Product licence (#148 LC-10).** #148 records a *proposed* product-licence
   boundary with proprietary terms for future work. The 2026-09-27 direction
   describes the initial release as **open source**, and `LICENSE` is MIT.
   Confirm whether 1.0 ships under MIT. If it does, LC-10 reduces to keeping
   the MIT lineage and attribution accurate under the new name. Either way,
   `LICENSE`'s "MacDown 2 is free and open-source software" line needs
   deliberate wording for the new name; #158 does not authorise that edit.
2. **Repository name** (#158 §2). Recommendation: `Joncallim/mostlytext`.
   GitHub redirects old clone and web URLs after a rename.
3. **Bundle ID** (#158 §1, #18). Recommendation: `app.mostlytext.MostlyText`,
   based on the owned domain, or keep the `com.joncallim.` prefix. Changing
   the ID means E17 must migrate `com.joncallim.MacDown2` defaults, Application
   Support, session and recovery state.
4. **CLI name** (#158 §1). Today it is `macdown2`. Recommendation:
   `mostlytext`, with `macdown2` kept as a compatibility alias through 1.x if
   the migration rehearsal needs it.
5. **Version scheme.** Recommendation: marketing version `1.0.0` and a
   `CFBundleVersion` that only ever increases, set by the release build.
   Sparkle compares `CFBundleVersion`.
6. **Distribution and hosting.** Recommendations:
   - A notarised, stapled **DMG** on GitHub Releases.
   - The Sparkle appcast at `https://mostlytext.app/appcast.xml`.
   - The website and LC-09 archive on a static host serving `mostlytext.app`.
   Decide where the website source lives: a `website/` folder here or a
   separate repository.
7. **Apple Developer Program.** Confirm membership and Team ID. Choose where
   notarisation credentials live: local keychain only, or CI secrets if E17
   signs in CI as its issue states.
