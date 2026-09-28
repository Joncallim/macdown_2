# Mac tranche: Developer ID signing, notarisation, DMG and clean-install check

**Owner summary.** This is the Mac-only part of the release pipeline, run as
one bounded session on the owner's Mac. It:
- confirms the Apple Developer account's Team ID and the Developer ID
  signing certificate, creating the certificate first if it doesn't exist;
- builds a Release candidate with the hardened runtime (macOS's
  code-integrity protection, which notarisation requires);
- signs, notarises and staples it (stapling attaches Apple's approval ticket
  to the file, so Gatekeeper can check it offline);
- packages it as a signed, notarised DMG;
- checks that a fresh install opens cleanly through Gatekeeper, macOS's
  download check.

The aim is to prove the whole pipeline and fix any signing or entitlement
problem now, rather than during E17. It publishes nothing.

**Status: ready to run.** Apple Developer Program enrolment is confirmed. Run
this now, on current `master`.

**What it builds.** The app still has its development identity
(`MacDown2.app`, `com.joncallim.MacDown2`, CLI `macdown2`) because the #158
identity cutover waits for E22. This run produces a *pre-cutover candidate*
that proves the pipeline. E17 repeats the same script on the real
MostlyText release candidate. Nothing this run produces is ever published.

Everything else about the release (licensing, website, planning, CI) stays in
cloud sessions.

## Rules

1. **Never publish.** No GitHub Release, tag, appcast, website deploy,
   notarised file upload, or push to `master`. Changes and evidence go on a
   branch through a pull request.
2. **No credentials in the repository, logs or screenshots.** That covers
   certificates, `.p12`/`.cer`/`.p8` files, private keys, app-specific
   passwords, App Store Connect API keys, and keychain profile contents.
   Record only the certificate's common name, the Team ID, notarisation
   submission IDs and statuses, and hashes. The Team ID isn't secret (it's in
   every signature), but keep it out of `project.yml` for now: the script
   takes it as input, and E17 decides how the release build receives it.
3. **Stop and report** instead of improvising if any of these happen: the
   Apple account lacks the role needed to create a Developer ID certificate;
   notarisation rejects something that needs a code or architecture change;
   or the app needs an entitlement that isn't covered by step 4 below.
   Report the exact output; the fix is planned in the cloud.
4. **Only the changes listed here.** Don't change app code, and don't add
   entitlements "just in case".

## Step 0: Team ID and Developer ID certificate (first bounded step)

1. Find the Team ID: developer.apple.com → Account → Membership details.
   Record it.
2. Check for an existing certificate:
   `security find-identity -v -p codesigning | grep "Developer ID Application"`.
   A line ending in `(<TEAM_ID>)` means it exists; go to step 1.
3. If it doesn't exist, create it in Xcode: Settings → Accounts → select the
   team → Manage Certificates → **+** → **Developer ID Application**. This
   needs the **Account Holder** role, which the owner has as an individual
   enrollee. Xcode generates the private key in the login keychain and never
   writes it to disk.
4. **Back up the private key outside the repository.** Export the identity
   from Keychain Access as a password-protected `.p12`, and store the file
   and its password in the owner's password manager. Losing it means
   creating a new certificate, not a lost release, but a backup avoids that.
   Never put the `.p12` anywhere under the repository.
5. Create the notarisation keychain profile, stored only in the keychain:
   `xcrun notarytool store-credentials mostlytext-notary --apple-id <id> --team-id <TEAM_ID>`
   (it prompts for an app-specific password from appleid.apple.com), or use
   `--key/--key-id/--issuer` with an App Store Connect API key.
6. Run the preflight:
   `TEAM_ID=<TEAM_ID> NOTARY_PROFILE=mostlytext-notary release/macos/sign-notarize-dmg.sh --preflight-only`

## Step 1: build, sign, notarise and package

The script lands on `master` with PR #164. Until that merges, start from the
PR's branch instead of `origin/master`:

```sh
git fetch origin
git switch -c release/signing-dry-run origin/master   # or origin/claude/beautiful-ramanujan-bq0a0w before #164 merges
TEAM_ID=<TEAM_ID> NOTARY_PROFILE=mostlytext-notary release/macos/sign-notarize-dmg.sh
```

`release/macos/sign-notarize-dmg.sh` stops at the first failure. It does the
following:

1. **Release build** of the app and the CLI with the hardened runtime, the
   Developer ID identity and secure timestamps.
2. **Signature check.** It verifies that every Mach-O binary is signed by
   this Team ID's Developer ID, with the hardened runtime and a timestamp.
3. **Notarise the app** (zipped), save Apple's log, and staple the app.
4. **Notarise the CLI.** A bare command-line binary can't be stapled, so
   Gatekeeper checks it online.
5. **Build the DMG,** containing the app and an Applications shortcut. Then
   sign it, notarise it and staple it.
6. **Validate** with `stapler validate`, `spctl` (app and DMG),
   `codesign --verify`, and `syspolicy_check distribution`, Apple's
   pre-distribution check.
7. **Record** SHA-256 hashes and run the licence gate against the signed app.
   That gate is expected to fail until the licences screen (LC-08) bundles
   the notices file.

Output goes to `build/release-<timestamp>/`, which is git-ignored.

## Step 2: hardened runtime and entitlements

The expected result is **hardened runtime with no entitlements**:
- The app isn't sandboxed (MIGRATION_PLAN D7).
- Diagram rendering uses WKWebView, whose web content runs in Apple's own
  processes, so the app needs no JIT (just-in-time compilation) entitlement.
- User text filters are started with `Process`, which the hardened runtime
  allows.

Confirm this with the smoke test in step 3.

- **If everything works:** make the setting permanent in a small PR. In
  `MacDown2/project.yml`, set `ENABLE_HARDENED_RUNTIME: YES` in the **Release**
  configuration of the `MacDown2` and `macdown2` targets only. Debug builds
  and CI's unsigned test runs stay unchanged, so tests are unaffected.
  Regenerate the project with `xcodegen generate` and confirm the Release
  build.
- **If a feature fails only under the hardened runtime:** capture the console
  error, identify the single entitlement it needs, re-run with
  `ENTITLEMENTS=<file>`, and commit that `.entitlements` file with the
  evidence explaining why it's needed. If more than one entitlement seems
  necessary, or the fix isn't obvious, **stop and report** (rule 3).

## Step 3: clean-install and Gatekeeper test

Use a fresh macOS 26 user account (System Settings → Users & Groups) or a
fresh macOS 26 virtual machine, so there are no existing preferences or
trust decisions.

1. Get the DMG into that account **with the quarantine flag set**, the way a
   real download would. AirDrop it, or download it with Safari from private
   storage. Confirm with
   `xattr -p com.apple.quarantine <dmg>`. If neither is possible, set the
   flag by hand and record that you did:
   `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <dmg>`.
2. Open the DMG. Record whether Gatekeeper shows any warning. None is
   expected for a notarised, stapled DMG.
3. Drag the app to Applications and launch it. Expect only the standard
   "downloaded from the Internet" confirmation, with Apple's malware check
   passed. Then disconnect from the network and launch again: it must open
   with no warning, which shows the stapled ticket works offline.
4. Smoke test, with the network off:
   - open a Markdown file;
   - preview a math block and Mermaid, Graphviz and D2 diagrams;
   - export to HTML and to PDF;
   - run one text filter;
   - quit and relaunch to check session restore.

   Record any feature that fails and the console errors (Console.app, filtered
   on the app).
5. CLI: copy `macdown2` to `~/bin` in the fresh account, run
   `macdown2 formats`, and record any Gatekeeper prompt.
6. Remove the test account or VM afterwards.

## Evidence to return

Open **one pull request** from `release/signing-dry-run` containing:

- `planning/evidence/<YYYY-MM-DD>/signing-dry-run/`:
  - `README.md`: commit SHA, macOS and Xcode versions, the certificate's
    common name, the Team ID, and a pass/fail table for steps 0 to 3. Mark
    anything skipped as `unverified`, never passed
    (`planning/RELEASE_EVIDENCE.md`).
  - From the script's `evidence/` folder: `summary.txt`, `verify.txt`,
    `macho-signatures.txt`, `codesign-display-*.txt`, `notary-*-submit.json`,
    `notary-*-log.json`, `SHA256SUMS`, `compliance-artifact.txt`. These
    contain no secrets. Read them once before committing anyway.
  - The clean-install and smoke-test results, with screenshots of the
    Gatekeeper dialogs. Screenshots must show no keychain or account details.
- If step 2 passed cleanly: the Release-only hardened-runtime change to
  `project.yml`. If an entitlement was needed: its file and the reason.

**Do not commit** the DMG, the zips, the app, the `DerivedData` folder or
`run.log` (the log is only for your own debugging). They stay in the
git-ignored `build/` folder.

The cloud coordinator reviews the PR, reconciles `RELEASE_PATH.md` and #18,
and plans any fix.
