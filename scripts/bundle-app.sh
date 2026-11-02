#!/bin/bash
# Build the SwiftPM executable and assemble + ad-hoc sign build/FileMaster.app (ADR-005).
# Usage: scripts/bundle-app.sh [debug|release]
set -euo pipefail
CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product FileMaster
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/FileMaster.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/PlugIns"
cp "$BIN/FileMaster" "$APP/Contents/MacOS/FileMaster"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts" # Fira Code (OFL), see ATSApplicationFontsPath

codesign --force --sign - --options runtime --entitlements Resources/FileMaster.entitlements "$APP" >/dev/null
echo "$APP"
