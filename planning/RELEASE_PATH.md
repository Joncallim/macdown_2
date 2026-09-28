# MostlyText 1.0 release path

**Owner summary.** This is the coordination map from today's `master` to a
public, signed and downloadable MostlyText 1.0. It adds no scope. Every item
below already has an owning issue or epic, and those issues remain the
binding contracts. This page shows:
- the order the work must happen in;
- what can start now;
- which steps need a Mac rather than a cloud session;
- the owner decisions that fix the release identity (§4).

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

Status as of 2026-09-27, after #136 merged (`d13f3d1`). Owner decisions
recorded 2026-09-28 (§4).

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
| Branding cutover (repository, README, public copy) | #158 | Record only. #158 runs after E22 | Cloud | Inputs are decided (§4). Execute once E22 closes: rename the repository to `Joncallim/mostlytext`, rebrand the README and public copy, and classify the remaining `MacDown 2` references as #158 §4 requires |
| App-icon integration | E23 (#113); inputs from #158 | No. E23 follows #158 | Cloud edits; **Mac** to verify | Move `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon` into the app **next to** `Assets.xcassets`, not inside it, and remove `AppIcon.appiconset` and the placeholder script. See that folder's README (D-028). Verify in a Release build in the Dock and Finder, light and dark |
| Bundle identity and versioning | Strategy: #158. Migration: #18 | Decided | Cloud | Decided (§4): `app.mostlytext.MostlyText`, CLI `mostlytext`, version `1.0.0` with independent build numbers. Today the app is `com.joncallim.MacDown2`, `0.1.0 (1)`, CLI `macdown2`. E17 owns the switch and the migration of development-namespace state; E23 derives its Quick Look and theme identifiers from the new prefix |
| Licensing and notices | #148 (LC-01–LC-10) | **Yes.** LC-02–LC-07 are identity-neutral | Cloud | 1.0 ships under MIT; #148 LC-10 was reframed on 2026-09-28 to match. Third-party notices (LC-01 to LC-09) stay a hard gate. LC-05 (make SwiftTreeSitter immutable) needs a lock file, not a manifest pin: a `revision:` pin fails resolution because Neon's own manifest requires SwiftTreeSitter `branch: "main"`, and SwiftPM refuses two different revision-based requirements (CI, 2026-09-28). The fix is a committed `Package.resolved` that CI enforces, generated on a Mac (details in #148). Next: LC-04 (TreeSitterMarkdown provenance), then the SBOM and notice generator (LC-01/07). LC-08's About → Licences UI must land before the final E16 freeze |
| Trademark | D-031 | Nothing for 1.0 | — | Ship with no "®" and no clearance claim. Revisit if MostlyText gains material adoption, revenue or sponsorship, press recognition, third-party brand use or other brand value |
| Signing and notarisation | E17 (#18) | **Waiting on Apple enrolment** | **Mac** | Enrolment is in progress (2026-09-28). This is an active dependency being resolved, not a release-risk decision. Once Apple approves it and the Team ID and Developer ID certificate exist, a Mac session runs a non-publishing Developer ID and notarisation dry run on current `master` (§3) to find hardened-runtime and entitlement problems early. Until then all signing work stays paused, and all other release work continues. No entitlements file exists yet, and the hardened runtime isn't enabled |
| Packaging and downloads | E17 (#18) | Decided; build at E17 | Cloud plans; Mac builds | Decided (§4): a signed, notarised DMG on GitHub Releases, linked from `mostlytext.app`. The Sparkle EdDSA key is generated once, on a Mac, and stored in the owner's keychain or password manager, never in the repository |
| Website and deployment | E17 (#18); LC-09 (#148) | Yes, as a draft | Cloud | Nothing exists in the repository yet. Build a static site at `mostlytext.app` (the public download page) covering the download, appcast, `/opensource` compliance archive (LC-09) and privacy statement. Public copy claims only capabilities with release evidence |
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
the table. It is held until Apple Developer Program enrolment is approved
and the Team ID and Developer ID certificate exist, and is queued then.

## 4. Owner decisions (2026-09-28)

These fix the inputs #158 freezes and E17 applies.

| Topic | Decision |
|---|---|
| Product licence | **MIT** for 1.0 and normal 1.x releases, continuing MacDown's lineage. The proposed proprietary boundary in #148 LC-10 is withdrawn for 1.0, and LC-10 is reframed to keep the MIT licence and attribution accurate under the new name. Third-party licence notices, source availability and the SBOM check (LC-01 to LC-09) remain a **hard release gate** |
| Repository | Rename to **`Joncallim/mostlytext`** during #158. GitHub redirects old clone and web URLs, but CI, badges and links are still checked deliberately |
| Bundle ID | **`app.mostlytext.MostlyText`** (canonical). Extensions and theme or document identifiers use the `app.mostlytext.` prefix. E17 migrates state from the development ID `com.joncallim.MacDown2` |
| CLI | **`mostlytext`**. Whether `macdown2` survives as a temporary compatibility alias is an E17 migration detail, not a public name |
| Versioning | Marketing version starts at **1.0.0** and follows normal 1.x semantic versioning. `CFBundleVersion` is an **independent build number that only ever increases**, never reset per release (Sparkle compares it) |
| Distribution | Primary download is a **signed, notarised DMG on GitHub Releases**. **`mostlytext.app`** is the public download site. The appcast location and the website's source location are E17 architecture details that follow from this, with `https://mostlytext.app/appcast.xml` as the default |
| Apple Developer Program | Treated as **required** for public release: Developer ID signing and notarisation depend on it |

**Apple Developer Program status (2026-09-28): enrolment in progress.** This
is an active dependency being resolved, not a release-risk decision. Developer
ID signing, notarisation and the Mac dry run stay paused until Apple approves
the enrolment and the Team ID and certificate are available. All other release
work continues meanwhile.
