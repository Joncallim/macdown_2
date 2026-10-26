# MostlyText 1.0 release path

## Execution checkpoint (2026-10-26)

The 2026-09-28 status and workstream table below are historical snapshots. The
adopted sequence is [RELEASE_SEQUENCE.md](RELEASE_SEQUENCE.md) (merged in PR
#147): stabilise software and interface (S), validate a private signed
candidate (V1), finish E16 localisation, validate the final signed candidate
and its exact-artifact compliance, close #115, perform #158's repository
cutover, then seek separate authority for public app promotion. The unit graph
in `downstream/readiness.json` records dependencies, not completed tests.

Current development base is `origin/integration-final` `11213c89`; the local
branch named `integration-final` may lag and must not be assumed current. PR
#480 (integration into `master`) is still draft. Merged #515 protects the #53
destination decoder but does not activate import; #516 adds localisation
inventory checks but does not freeze strings; #517 locks release dependencies
but does not establish a signed artifact; #518 fixes saved HTML load identity
but does not make the live preview's resource reads contained. These parent
issues remain open.

The first concurrent source lanes are #121's explicit window-local resource
grant and #509's sidebar/encoding reconciliation. One Mac owner at a time
handles Release builds and native interface tests. #121's folder-choice policy
is settled, but both HTML and Markdown consumers, the chooser and signed native
permission evidence must pass before closure. #509 requires observed native
acceptance before merge. #505's fresh Trash action remains held. Do not treat
green CI or private older-app evidence as acceptance for a changed head.
The local #121 branch `fix/121-preview-contained-read-2026-10-26` contains
reviewed test checkpoints `4fb535cc` and `462e984e`, followed by the combined
source checkpoint `53ca9436`; it has not passed native or signed acceptance.

| Order | Owning issues and bounded outcome | Required evidence before closure or next stage |
| --- | --- | --- |
| 1, parallel source work | #121: explicit folder grant, contained HTML and Markdown reads, safe revocation; #509: sidebar/encoding reconciliation. #505 remains separate. | #121 race, two-window, Save As, cancellation, renamed-root and long-document tests plus signed native behavior. #509 needs exact-build sidebar/encoding dogfood. #505 needs a fresh approved Trash test. Each merged slice needs independent review and applicable exact-head CI. |
| 2 | E22/#112 and #173: reconcile remaining editing and native navigation journeys; #116–#121, #117, #118, #120, #183 and #459: finish only their documented residuals. #119 owns external-file manual/performance evidence. | Real Release workflows and focused regressions, followed by issue-by-issue review, CI, dogfood and risk records. #203 gets an explicit E05 performance disposition; a new fork/pin remains a separate decision. |
| 3 | E23/#113 and #79: finish theme catalog, Appearance, Quick Look, Finder and coherent diagrams. #53 and app-side E17/#18: consented migration, state compatibility, CLI and updater after E22/E23 contracts. | Theme/contrast, file/import/recovery, Quick Look/Finder, three-engine and migration/restart evidence. Existing #515 decoder protection is not importer activation. |
| 4 | S and private V1: #88 interface gaps, #155 long-session/memory, and the finite #115 debt ledger on one identified candidate. | Executed critical native cases including accessibility, recovery, export and update paths. Any required blocked or skipped result returns to S; compilation alone is insufficient. |
| 5 | Final E16/#17 translation and string freeze after V1. | Actual extraction, translation, native-language and layout review. #516 only validates inventory structure. |
| 6 | Final signed E17/#18 candidate and #148 exact-artifact provenance, source offers, notices and licence UI. | Notarisation, install/update rehearsal, artifact hashes, anonymous source downloads, qualified Mermaid notice review, and artifact/locale-sensitive #115 reruns. #517 only hardens dependency resolution. |
| 7 | Close #115, then #158 full-history repository cutover; public promotion is separate. | Frozen source/artifact identity, new-repository CI and real post-cutover commit, then explicit publication authority. |

After E22 (#112) and its navigation/evidence debts converge, finish E23 (#113)
and #53/E17 app-side migration contracts. In parallel, close concrete
#116–#121, #79, #88, #155, #173, #183 and #459 obligations against their
own issue criteria. #203's dependency/pin change is a separate decision, not
an implicit performance workaround. The S gate is a reviewable ledger, not a
claim that these open parent issues are complete. Native file, recovery,
preview, export, math, diagram, theme, accessibility and long-session cases
belong to the exact private candidate. Only after V1 passes do final E16
translation and the final signed candidate/#148 artifact checks proceed.

Source-only D2/Graphviz distribution and the matching open-source pages were
published and verified earlier; this did not publish the app. A Developer ID
identity and a local signed-build check exist, but notarisation, the final
signed app and human Mermaid notice review are still gates. Website quality
assurance is owned separately. No source branch or issue closure authorises a
public app release, storage migration, new dependency, changed permissions or
paid service.

**Owner summary.** This is the coordination map from today's `master` to a
public, signed and downloadable MostlyText 1.0. It adds no scope. Every item
below already has an owning issue or epic, and those issues remain the
binding contracts. This page shows:
- the order the work must happen in;
- what can start now;
- which steps need a Mac rather than a cloud session;
- the owner decisions that fix the release identity (§4).

The brand identity is now frozen for 1.0: design gates 1 and 2 are closed,
gate 3 was waived (D-026) and gate 4 is deferred by the owner (D-031), not
passed. Brand decisions are
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

Status as of 2026-09-28, at `master` `8a05703`. Owner decisions recorded
2026-09-28 (§4).

## 1. Critical path

This is the hard order set by #158, `planning/RELEASE_HARDENING.md` and E17
(#18):

```text
E22 (#112) ─▶ identity inputs (#158) ─▶ E23 (#113) ─▶ S (software + UI stabilised, incl. #116–#121, #88, #79, #53)
    ─▶ private candidate 1 + software/native #115 verification (V1)
    ─▶ final E16 string freeze (#17)
    ─▶ final signed candidate 2 (needs the corresponding source already published, #148)
        + #148 exact-artifact compliance + artifact/locale-sensitive #115 reruns
    ─▶ #115 closes ─▶ full-history repository cutover (#158) ─▶ separately authorised public promotion (#18)

Source-only corresponding-source publication (#148, owner-authorised) happens BEFORE candidate 2 and never
publishes an application binary. Details: planning/RELEASE_SEQUENCE.md and compliance/ARCHIVE_PLAN.md.
Can be prepared early, used at E17:
    Developer ID certificate + notarisation profile (Mac tranche), Sparkle EdDSA key,
    website/archive hosting
```

E22 is being delivered slice by slice by its own session. Slices 1–6 have
landed (6c, recent files, in PR #161); 7 (folder search/replace), 8 and 9
remain. Nothing on this page interrupts that work.

Two technical fixes that blocked this path have landed (updated 2026-09-28,
after the status line above). Each was done on its own:
- **FileCore red `master` — fixed by PR #166 (`82ae971`).** The recurring
  `parentVanishedLatchSurvivesAChangedEventDuringDebounce()` failure was a
  test-harness race, separate from the recorder-ordering race fixed in #154: a
  superseded debounce probe consumed the test's scripted prober answers. It
  was reproduced (21 of 900 loaded iterations) and fixed by gating the
  interleaving deterministically, with exact-sequence assertions and a new
  regression test for the other ordering. No skips, and no longer timeouts.
  Product code was unchanged.
- **LC-05 (SwiftTreeSitter immutability, #148) — landed in #165**, after being
  updated onto the corrected `master` and getting a fresh green CI run.
  `MacDown2/Packages/MacDownKit/Package.resolved` is committed and pins
  SwiftTreeSitter at `cbe31cb3601aa29c1f64b6e4328733511126d6d5` (still
  declared `branch: "main"`, because Neon requires it). CI builds only locked
  revisions:
  - `swift build`/`swift test` run with `--force-resolved-versions`;
  - the Xcode builds copy the lock into the generated project, pass
    `-onlyUsePackageVersionsFromResolvedFile`, then check the copy survived.

  The enforcement covers CI only. A plain local `xcodebuild` resolves on its
  own unless the pin step in `AGENTS.md` is used; the same applies to any
  future release pipeline that does not use that step. The lock fixes *which*
  revisions are built. Checking them against a registered inventory is LC-07's job, and LC-07 is still open.
  Changing the lock is a deliberate dependency update, reviewed like code.

## 2. Workstreams

| Workstream | Owning issue | Can start now? | Where | Next concrete step |
|---|---|---|---|---|
| Brand identity | D-001–D-031 (`design/`) | **Done for 1.0** | — | None. Rename the Figma file title from "(Slant 12°)" in the Figma UI (D-029) |
| Branding cutover (repository, README, public copy) | #158 | Record only. #158 runs after E22 | Cloud | Inputs are decided (§4). Consume the identity inputs now; the repository cutover itself is the late full-history mirror to `Joncallim/mostlytext` after #115 closes (critical path above) — the engineering backlog stays in `macdown_2` until then, so do not transfer issues or rename early. Rebrand the README and public copy at the cutover, and classify the remaining `MacDown 2` references as #158 §4 requires |
| App-icon integration | E23 (#113); inputs from #158 | No. E23 follows #158 | Cloud edits; **Mac** to verify | Move `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon` into the app **next to** `Assets.xcassets`, not inside it, and remove `AppIcon.appiconset` and the placeholder script. See that folder's README (D-028). Verify in a Release build in the Dock and Finder, light and dark |
| Bundle identity and versioning | Strategy: #158. Migration: #18 | Decided | Cloud | Decided (§4): `app.mostlytext.MostlyText`, CLI `mostlytext`, version `1.0.0` with independent build numbers. Today the app is `com.joncallim.MacDown2`, `0.1.0 (1)`, CLI `macdown2`. E17 owns the switch and the migration of development-namespace state; E23 derives its Quick Look and theme identifiers from the new prefix |
| Licensing and notices | #148 (LC-01–LC-10) | **Yes.** LC-02–LC-07 are identity-neutral | Cloud | 1.0 ships under MIT; #148 LC-10 was reframed on 2026-09-28 to match. Third-party notices (LC-01 to LC-09) stay a hard gate. LC-05 (make SwiftTreeSitter immutable) needs a lock file, not a manifest pin: a `revision:` pin fails resolution because Neon's own manifest requires SwiftTreeSitter `branch: "main"`, and SwiftPM refuses two different revision-based requirements (CI, 2026-09-28). That fix landed in #165: a committed `Package.resolved` that CI enforces (§1; evidence in #148). The gate itself is in `compliance/` (2026-09-28): a checked inventory of all 33 shipped components, generated notices and SBOM, and a CI check with negative tests. LC-04 and LC-06 provenance are recorded there. `compliance.py check --release` lists what remains. Next: Mermaid's bundled npm dependencies (LC-01), the Graphviz and D2 source packages (LC-02/03, plan in `compliance/ARCHIVE_PLAN.md`). The inventory is reconciled with the #165 lock file: all 22 pinned revisions are verified, and `lockfile_enforced` is on, so a lock change that the inventory doesn't match fails CI. LC-08's licences screen (`compliance/LICENCES_UI.md`) starts after E22 and must land before the final E16 freeze |
| Trademark | D-031 | Nothing for 1.0 | — | Registration and legal review are **deferred by the owner, not passed**. The WIPO, USPTO and IPOS search record, including the flagged Modern Tech Pte. Ltd. mark (Singapore 40201616062P), stays in `design/brand/TRADEMARK_SEARCH.md` unchanged. Ship with no "®" and no clearance claim. Revisit if MostlyText gains material adoption, revenue or sponsorship, press recognition, third-party brand use or other brand value |
| Signing and notarisation | E17 (#18) | **Yes: Mac tranche ready** | **Mac** | Apple Developer Program enrolment is confirmed. `planning/MAC_SIGNING_BRIEF.md` is the bounded Mac task. It first confirms the Team ID and the Developer ID Application certificate, creating the certificate if it's missing. It then runs `release/macos/sign-notarize-dmg.sh --dry-run`, which: does a Release build with the hardened runtime; checks every binary's signature; checks the built app against the licence inventory; notarises and staples the app; notarises the CLI ZIP; builds, signs, notarises and staples a DMG; and validates everything with codesign, spctl and syspolicy_check. Last comes a clean-install Gatekeeper test of the DMG and the CLI ZIP in a fresh account. **The mode is explicit:** `--dry-run` records incomplete release gates as UNVERIFIED and continues. `--release-candidate` (E17 only) needs a clean tree and stops on any licence-gate failure, before anything is sent to Apple, and on a missing notarisation log. This tranche is a pre-cutover pipeline proof under the development identity, and it publishes nothing. The expected outcome is hardened runtime with no entitlements, made permanent for Release builds only. How the CLI finally ships (inside the app or as a separate download) is still an E17 decision |
| Packaging and downloads | E17 (#18) | Decided; build at E17 | Cloud plans; Mac builds | Decided (§4): a signed, notarised DMG on GitHub Releases, linked from `mostlytext.app`. The Sparkle EdDSA key is generated once, on a Mac, and stored in the owner's keychain or password manager, never in the repository |
| Website and deployment | E17 (#18); LC-09 (#148) | Draft exists | Cloud | `website/` (2026-09-28) has a static draft of `mostlytext.app`: home and download, `/opensource` archive and privacy pages. **Not deployed.** Its README has a claims ledger; every public statement needs release evidence before E17 deploys it. Hosting and the appcast are E17 decisions |
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
the table, written in `planning/MAC_SIGNING_BRIEF.md`. Enrolment is
confirmed, so it is ready to run. If the Developer ID certificate doesn't
exist yet, creating it is the brief's first bounded step.

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

**Apple Developer Program status: enrolment confirmed** (owner, after
2026-09-28). It is no longer an open dependency. The Mac signing and
notarisation tranche (§2, §3) is ready to run.
