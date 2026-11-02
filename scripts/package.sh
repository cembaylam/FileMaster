#!/bin/bash
# Release build → signed app → DMG (→ notarized + stapled when credentials exist). See docs/DISTRIBUTION.md.
# Usage: scripts/package.sh
#   SIGN_ID="Developer ID Application: Name (TEAMID)"   signing identity (default: auto-detect Developer ID, else ad-hoc)
#   NOTARY_PROFILE=fm-notary                            notarytool keychain profile (skip notarization if unset)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/FileMaster.app"
ENT="Resources/FileMaster.entitlements"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="$ROOT/dist/FileMaster-$VERSION.dmg"

if [[ -z "${SIGN_ID:-}" ]]; then
    SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
SIGN_ID="${SIGN_ID:--}"

# 1. Release bundle (bundle-app.sh ad-hoc signs it; re-signed below).
scripts/bundle-app.sh release >/dev/null
strip -x "$APP/Contents/MacOS/FileMaster"

# 2. Sign inside-out: embedded frameworks/plugins first, then the app.
SIGN_ARGS=(--force --options runtime --sign "$SIGN_ID")
[[ "$SIGN_ID" != "-" ]] && SIGN_ARGS+=(--timestamp)
find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" -mindepth 1 -maxdepth 1 \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) -print0 2>/dev/null |
    while IFS= read -r -d '' item; do codesign "${SIGN_ARGS[@]}" "$item"; done
codesign "${SIGN_ARGS[@]}" --entitlements "$ENT" "$APP"
codesign --verify --strict --deep "$APP"

# 3. DMG: app + /Applications alias, LZFSE-compressed.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "FileMaster $VERSION" -srcfolder "$STAGE" -fs APFS -format ULFO "$DMG"
[[ "$SIGN_ID" != "-" ]] && codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

# 4. Notarize + staple (Developer ID only).
if [[ "$SIGN_ID" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    STATUS="Developer ID signed, notarized, stapled"
elif [[ "$SIGN_ID" != "-" ]]; then
    STATUS="Developer ID signed, NOT notarized (set NOTARY_PROFILE)"
else
    STATUS="ad-hoc signed (no Developer ID identity): recipients must clear quarantine"
fi

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"
echo "signing: $SIGN_ID — $STATUS"
