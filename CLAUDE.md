# FileMaster — session guide

A very fast, keyboard-first file manager for macOS on Apple Silicon. It looks like a native
Mac app and behaves like [yazi](https://yazi-rs.github.io): 3 columns (parent | current | preview),
previews for **every** file type (binary files included), a built-in image and video player, and native Swift plugins.

**Start every session by reading `docs/ROADMAP.md`** (current status and the next task). Then read whichever
of these docs the task touches:

| Doc | What's in it |
|---|---|
| `docs/DECISIONS.md` | Architecture Decision Records (ADRs). Append new ones; never silently change old ones |
| `docs/ARCHITECTURE.md` | Modules, threading model, data flow, performance techniques and budgets |
| `docs/PREVIEW.md` | Preview pipeline, how a previewer is chosen, and the per-type previewer catalog |
| `docs/MEDIA.md` | Image and video player, AVFoundation + FFmpeg fallback pipeline |
| `docs/PLUGINS.md` | Plugin SDK (`FMPluginKit`), bundle format, loader, crash safety |
| `docs/KEYMAP.md` | Default keybindings (yazi-compatible) and the keymap config format |
| `docs/CONFIG.md` | Config file locations and schema |
| `docs/DISTRIBUTION.md` | Signing, DMG packaging, notarization setup |

## Target environment (only this, no back-compat)

- macOS 27.2+, arm64 only (development machine: M1 Pro, 16 GB, ProMotion 120 Hz)
- Xcode 27.2, Swift 6.4 with strict concurrency (Swift 6 language mode)
- Homebrew at `/opt/homebrew`; `ffmpeg` is installed through brew

## Build

SwiftPM plus a `Makefile`. No checked-in `.xcodeproj` (open `Package.swift` in Xcode to debug).

```
make app               # release build → build/FileMaster.app (ad-hoc signed, hardened runtime)
make run               # debug bundle, relaunch via `open`
make dev DIR=~/foo     # debug bundle, run in the foreground (logs in the terminal)
make test              # swift test (Swift Testing)
make bench DIR=/path   # fm-bench: getattrlistbulk vs FileManager, sort timings
make dist              # signed DMG → dist/ (notarized when NOTARY_PROFILE set; docs/DISTRIBUTION.md)
```

Code map: `Sources/FMCore` (FS listing, cache, watcher, sorting, keymap engine + keymap.toml, FileOps, Walker/Fuzzy search,
GitStatus; no AppKit),
`Sources/FMPreview` (preview loaders, syntax lexers), `Sources/FMApp` (AppKit: window/tabs, `BrowserViewController` =
navigation state with feature extensions +Ops/+Find/+Overlays, `FileListView` = custom-drawn list, `PromptView`/`PickerView`
overlays, `Prefs`, `TaskCenter`, `ScriptDriver` for debug UI scripting), `Sources/fm-bench`, `Tests/`.

## Rules for working on this repo

- Performance is the top feature. Before adding work to the main thread, check the budgets in ARCHITECTURE.md.
- No sandbox. Hardened runtime with `disable-library-validation` so plugins can load (ADR-004, ADR-006).
- Keep it native: AppKit for anything hot; SwiftUI only for settings and dialogs that don't matter for speed.
- Any non-obvious design choice gets an ADR in `docs/DECISIONS.md`.
- Update `docs/ROADMAP.md` checkboxes and the "Status / next step" section at the end of each session.
- Git repo: https://github.com/cembaylam/FileMaster (public, MIT, default branch `main`). Commit/push only when asked; release DMGs go to GitHub Releases, never into the repo.
