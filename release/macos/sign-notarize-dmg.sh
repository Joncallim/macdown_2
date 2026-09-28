#!/usr/bin/env bash
# Build, sign, notarise and package MostlyText (currently MacDown2.app) as a
# Developer ID DMG, and record evidence. Runs on the owner's Mac only.
#
# What it does, in order (stops at the first failure):
#   1. preflight  Team ID, Developer ID Application identity, notarytool profile
#   2. build      Release build of the app and CLI with the hardened runtime
#   3. sign-check confirm Xcode signed every Mach-O binary with this Developer
#                 ID, the hardened runtime and a secure timestamp
#   4. notarise   submit the app (zip) and CLI (zip), wait, save logs, staple the app
#   5. dmg        build a DMG (app + /Applications link), sign, notarise, staple
#   6. verify     codesign, spctl, stapler validate, syspolicy_check
#
# Secrets never pass through this script or its logs. Signing uses the
# certificate already in the login keychain; notarisation uses a keychain
# profile created beforehand with `xcrun notarytool store-credentials`.
# Evidence records only certificate names, the Team ID, submission IDs,
# statuses and hashes.
#
# Usage:
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=mostlytext-notary \
#     release/macos/sign-notarize-dmg.sh [--preflight-only]
#
# Optional environment:
#   ENTITLEMENTS  path to an .entitlements file (default: none)
#   OUT           output directory (default: build/release-<UTC timestamp>)
#   LABEL         DMG name suffix (default: devid-dryrun). Never "release"
#                 unless E17's release process is running this.

set -euo pipefail

: "${TEAM_ID:?set TEAM_ID to the Apple Developer Team ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to the notarytool keychain profile name}"
ENTITLEMENTS="${ENTITLEMENTS:-}"
LABEL="${LABEL:-devid-dryrun}"
PREFLIGHT_ONLY=0
[[ "${1:-}" == "--preflight-only" ]] && PREFLIGHT_ONLY=1

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT:-$REPO/build/release-$STAMP}"
EVIDENCE="$OUT/evidence"
DERIVED="$OUT/DerivedData"
APP_NAME="MacDown2"   # becomes MostlyText at the #158/E17 cutover
CLI_NAME="macdown2"   # becomes mostlytext at the #158/E17 cutover
mkdir -p "$EVIDENCE"
exec > >(tee -a "$EVIDENCE/run.log") 2>&1

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nSTOP: %s\n' "$*"; exit 1; }
record() { printf '%s\n' "$*" >> "$EVIDENCE/summary.txt"; }

record "commit: $(git -C "$REPO" rev-parse HEAD)"
record "dirty: $(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') changed paths"
record "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
record "xcode: $(xcodebuild -version | tr '\n' ' ')"
record "team: $TEAM_ID"

# ---------------------------------------------------------------- 1. preflight
step "Preflight: Developer ID Application identity for team $TEAM_ID"
IDENTITIES="$(security find-identity -v -p codesigning)"
IDENTITY_LINE="$(grep "Developer ID Application: .*($TEAM_ID)" <<<"$IDENTITIES" | head -n 1 || true)"
[[ -n "$IDENTITY_LINE" ]] || fail "no valid 'Developer ID Application: … ($TEAM_ID)' identity in the keychain. Create it first (brief step 0)."
IDENTITY="$(sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' <<<"$IDENTITY_LINE")"
record "identity: $IDENTITY"
echo "Using: $IDENTITY"

step "Preflight: notarytool profile '$NOTARY_PROFILE'"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null \
  || fail "notarytool profile '$NOTARY_PROFILE' is missing or rejected. Create it with xcrun notarytool store-credentials."
record "notary profile: present"

if [[ -n "$ENTITLEMENTS" ]]; then
  [[ -f "$ENTITLEMENTS" ]] || fail "ENTITLEMENTS file not found: $ENTITLEMENTS"
  record "entitlements: $ENTITLEMENTS ($(shasum -a 256 "$ENTITLEMENTS" | cut -d' ' -f1))"
else
  record "entitlements: none"
fi

if (( PREFLIGHT_ONLY )); then
  echo "Preflight passed. Evidence: $EVIDENCE"
  exit 0
fi

# ---------------------------------------------------------------- 2. build
step "Generate the Xcode project"
(cd "$REPO/MacDown2" && xcodegen generate)

build() {  # $1 scheme, $2 "app" to apply ENTITLEMENTS
  local extra=()
  [[ -n "$ENTITLEMENTS" && "${2:-}" == "app" ]] && extra+=(CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS")
  xcodebuild -project "$REPO/MacDown2/MacDown2.xcodeproj" -scheme "$1" \
    -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
    ${extra[@]+"${extra[@]}"} build
}
step "Release build: $APP_NAME"
build "$APP_NAME" app
step "Release build: $CLI_NAME"
build "$CLI_NAME"

PRODUCTS="$DERIVED/Build/Products/Release"
APP="$PRODUCTS/$APP_NAME.app"
CLI="$PRODUCTS/$CLI_NAME"
[[ -d "$APP" ]] || fail "app not produced at $APP"
[[ -f "$CLI" ]] || fail "CLI not produced at $CLI"
record "version: $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) ($(defaults read "$APP/Contents/Info" CFBundleVersion))"
record "bundle id: $(defaults read "$APP/Contents/Info" CFBundleIdentifier)"

# ---------------------------------------------------------------- 3. sign-check
# Xcode signs the app, its nested code and the CLI from the build settings
# above. SwiftPM code is linked statically; its resource bundles hold data,
# not code. Check every Mach-O binary rather than re-signing blindly.
step "Check signatures"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee "$EVIDENCE/codesign-verify-app.txt"
codesign --verify --strict --verbose=2 "$CLI" 2>&1 | tee "$EVIDENCE/codesign-verify-cli.txt"
codesign -dvvv --entitlements - "$APP" > "$EVIDENCE/codesign-display-app.txt" 2>&1
codesign -dvvv "$CLI" > "$EVIDENCE/codesign-display-cli.txt" 2>&1
: > "$EVIDENCE/macho-signatures.txt"
while IFS= read -r -d '' binary; do
  file -b "$binary" | grep -q 'Mach-O' || continue
  info="$(codesign -dvv "$binary" 2>&1 || true)"
  rel="${binary#"$PRODUCTS"/}"
  grep -q "Authority=Developer ID Application: .*($TEAM_ID)" <<<"$info" || fail "$rel is not signed with the Developer ID identity"
  grep -q 'Timestamp=' <<<"$info" || fail "$rel has no secure timestamp"
  grep -Eq 'flags=0x[0-9a-f]+\(.*runtime' <<<"$info" || fail "$rel lacks the hardened runtime"
  echo "ok  $rel" >> "$EVIDENCE/macho-signatures.txt"
done < <(find "$APP" "$CLI" -type f -print0)
record "mach-o binaries checked: $(wc -l < "$EVIDENCE/macho-signatures.txt" | tr -d ' ')"

# ---------------------------------------------------------------- 4. notarise
notarise() {  # $1 file to submit, $2 evidence name
  local json id status
  json="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  printf '%s\n' "$json" > "$EVIDENCE/notary-$2-submit.json"
  id="$(/usr/bin/plutil -extract id raw -o - - <<<"$json")"
  status="$(/usr/bin/plutil -extract status raw -o - - <<<"$json")"
  xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$EVIDENCE/notary-$2-log.json" || true
  record "notarisation $2: $id $status"
  [[ "$status" == "Accepted" ]] || fail "notarisation of $2 returned '$status'; see notary-$2-log.json"
}
step "Notarise the app"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
notarise "$OUT/$APP_NAME.zip" app
xcrun stapler staple "$APP"
step "Notarise the CLI (a bare binary can't be stapled; Gatekeeper checks it online)"
ditto -c -k "$CLI" "$OUT/$CLI_NAME.zip"
notarise "$OUT/$CLI_NAME.zip" cli

# ---------------------------------------------------------------- 5. dmg
VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
DMG="$OUT/$APP_NAME-$VERSION-$BUILD-$LABEL.dmg"
step "Build the DMG"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
step "Notarise the DMG"
notarise "$DMG" dmg
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------- 6. verify
step "Verify"
{
  echo "## stapler validate app";  xcrun stapler validate "$APP"
  echo "## stapler validate dmg";  xcrun stapler validate "$DMG"
  echo "## spctl exec (app)";      spctl --assess --type execute --verbose=4 "$APP"
  echo "## spctl open (dmg)";      spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
  echo "## codesign verify (dmg)"; codesign --verify --verbose=2 "$DMG"
  if command -v syspolicy_check >/dev/null; then
    echo "## syspolicy_check distribution"; syspolicy_check distribution "$APP"
  fi
} 2>&1 | tee "$EVIDENCE/verify.txt"

step "Hashes"
{
  shasum -a 256 "$DMG" "$OUT/$APP_NAME.zip" "$CLI"
} | tee "$EVIDENCE/SHA256SUMS"

step "Licence gate against the signed app (evidence; failures expected until LC-08)"
python3 "$REPO/compliance/tools/compliance.py" check --release --artifact "$APP" \
  > "$EVIDENCE/compliance-artifact.txt" 2>&1 || true

echo
echo "Done. DMG: $DMG"
echo "Evidence: $EVIDENCE (contains no secrets; review before committing)"
