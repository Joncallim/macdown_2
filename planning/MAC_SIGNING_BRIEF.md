# Mac brief: Developer ID signing and notarisation dry run

**Owner summary.** This is the first and only Mac task queued for release. It
signs a Release build of the app and CLI with a Developer ID certificate,
turns on the hardened runtime (macOS's code-integrity protection, which
notarisation requires), submits the build to Apple's notarisation service,
and records what happens. The aim is to find signing and entitlement problems
months before release, not during E17. It publishes nothing.

**Status: held.** Apple Developer Program enrolment is in progress
(`planning/RELEASE_PATH.md` §4). Run this brief only after Apple approves the
enrolment and the Team ID and a "Developer ID Application" certificate exist
in the owner's keychain. Until then, nothing in it can run.

Everything else about the release (licensing, website, planning, CI) stays in
cloud sessions. The Mac is used only because this work needs the owner's
certificate and Apple's tools.

## Scope

| In scope | Out of scope |
|---|---|
| Release build of current `master` (app and `macdown2` CLI) as they are today, under the development identity | The #158 identity cutover (bundle ID, names), which comes later |
| Hardened runtime, Developer ID signature with secure timestamp | Choosing or adding entitlements beyond what the evidence shows is needed |
| `notarytool` submission, `stapler`, `spctl` assessment | Creating a DMG for distribution, Sparkle, the appcast, any GitHub Release |
| Running the licence gate against the signed app | Changing app code (report findings instead) |

## Inputs

- Commit: the current `master` head at the time of the run. Record the full
  SHA.
- Credentials, all kept outside the repository: the Developer ID Application
  certificate in the login keychain; a `notarytool` keychain profile created
  with `xcrun notarytool store-credentials` (an app-specific password or App
  Store Connect API key, owner's choice).

## Steps

```sh
git -C <clone> checkout <sha>
cd MacDown2 && xcodegen generate && cd ..

# 1. Release build, signed with the hardened runtime.
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=<TEAM_ID> ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS=--timestamp build
# Repeat for the macdown2 CLI scheme, with the same settings.

# 2. Inspect the signatures.
codesign --verify --deep --strict --verbose=2 build/dd/Build/Products/Release/MacDown2.app
codesign -dvv --entitlements - build/dd/Build/Products/Release/MacDown2.app
codesign --verify --strict --verbose=2 build/dd/Build/Products/Release/macdown2

# 3. Notarise (zip for submission) and staple.
ditto -c -k --keepParent build/dd/Build/Products/Release/MacDown2.app build/MacDown2.zip
xcrun notarytool submit build/MacDown2.zip --keychain-profile <profile> --wait
xcrun notarytool log <submission-id> --keychain-profile <profile> build/notary-log.json
xcrun stapler staple build/dd/Build/Products/Release/MacDown2.app
spctl --assess --type execute --verbose=4 build/dd/Build/Products/Release/MacDown2.app

# 4. Smoke test the signed app: launch it; open a Markdown file; show the
#    preview with a math block, a Mermaid, a Graphviz and a D2 diagram;
#    export to HTML and to PDF. WebKit-based diagram rendering is the most
#    likely thing to need an entitlement under the hardened runtime.

# 5. Licence gate against the signed app (evidence only; failures are expected
#    until LC-08 bundles the notices).
python3 compliance/tools/compliance.py check --release \
  --artifact build/dd/Build/Products/Release/MacDown2.app
```

## Rules

1. **Never publish.** No GitHub Release, tag, appcast, website deploy or push
   to `master`.
2. **Never commit or show credentials.** No certificates, `.p12`/`.p8`
   files, passwords or keychain profile contents in the repository, logs or
   screenshots. Record only the certificate's common name, the Team ID,
   submission IDs, statuses and hashes.
3. **Stop and report** on a missing credential, a notarisation rejection that
   needs a code or architecture change, or a hardened-runtime failure that
   needs an entitlement. Report the exact failure. Don't add entitlements or
   change code to get past it; the fix is planned and reviewed in the cloud.

## Evidence to return

Commit it under `planning/evidence/<YYYY-MM-DD>/signing-dry-run/` on a
branch, and open a pull request:

- `README.md`: commit SHA, Xcode and macOS versions, certificate common name
  and Team ID, and a pass/fail table for steps 1 to 5.
- The `codesign -dvv` output, the notarisation log JSON (it contains no
  secrets) and the `spctl` output.
- The SHA-256 of the signed app zip and of the CLI binary.
- The smoke-test result for each diagram engine and export path, with any
  console errors.
- The `compliance.py --artifact` output.

Unavailable or skipped steps are recorded as `unverified`, never as passed
(`planning/RELEASE_EVIDENCE.md`).
