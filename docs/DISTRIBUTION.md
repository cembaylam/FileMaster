# Distribution: signing and packaging

`make dist` (→ `scripts/package.sh`) produces `dist/FileMaster-<version>.dmg` plus a `.sha256` file.
The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`. Bump it (and `CFBundleVersion`)
before each release.

## Pipeline
1. `scripts/bundle-app.sh release`, then `strip -x` on the binary.
2. Code-sign inside-out: everything in `Contents/Frameworks` and `Contents/PlugIns` first, then the app, with
   hardened runtime, `Resources/FileMaster.entitlements` (`disable-library-validation`, ADR-004/006), and a
   secure timestamp when using a real identity. Then run `codesign --verify --strict --deep`.
3. DMG: the app plus an `/Applications` symlink. APFS, `ULFO` (LZFSE) compression. The DMG itself gets signed
   when using a real identity.
4. If `NOTARY_PROFILE` is set: `notarytool submit --wait`, then `stapler staple`, then `spctl --assess`.

The signing identity is `$SIGN_ID`, or the first "Developer ID Application" identity found in the keychain, or
ad-hoc (`-`) when there is none.

## Current state (2026-11-01)
This machine has **no Developer ID certificate** (only an unrelated self-signed "ShottrFree Dev"), so
`make dist` currently builds an **ad-hoc signed** DMG. That's fine for your own Macs. On another Mac, Gatekeeper
blocks it ("cannot be opened / damaged") because the download is quarantined. The recipient fixes it once with:

```
xattr -dr com.apple.quarantine /Applications/FileMaster.app
```
(or in System Settings → Privacy & Security → "Open Anyway" after the first attempt to open it).

## Going Gatekeeper-clean (one-time setup)
1. Join the Apple Developer Program ($99/yr).
2. Xcode → Settings → Accounts → Manage Certificates → **+ Developer ID Application**.
   `security find-identity -v -p codesigning` should list it.
3. Create an app-specific password at appleid.apple.com, then:
   `xcrun notarytool store-credentials fm-notary --apple-id <id> --team-id <TEAMID> --password <app-pw>`
4. `NOTARY_PROFILE=fm-notary make dist` → signed, notarized and stapled DMG that opens anywhere.

## Notes
- Fira Code (Regular + SemiBold, ~600 KB) ships in `Contents/Resources/Fonts` with `FiraCode-OFL.txt` (ADR-016).
- The binary is arm64 only and links only system libraries/frameworks (checked with `otool -L`). When the FFmpeg
  backend (M3) or FMPluginKit dylib (M7) lands, they must be copied into `Contents/Frameworks` and get their
  install names rewritten to `@rpath`. The script already signs anything placed there. Homebrew's ffmpeg dylibs
  can't be referenced from `/opt/homebrew` in a distributed build.
- Third-party plugin bundles are signed by their authors. `disable-library-validation` lets them load under a
  different Team ID.
- No auto-update (Sparkle) yet. Add it if the app gets other users.
