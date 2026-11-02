# Roadmap & status

Update the checkboxes and the **Status / next step** section at the end of every session.

## M0 — Skeleton
- [x] `Package.swift` (FMCore, FMPreview, FMApp, fm-bench, FMCoreTests). FMMedia/FMPluginKit/CFFmpeg are added in M2/M3/M7
- [x] `Makefile` + `scripts/bundle-app.sh` → `build/FileMaster.app`, Info.plist, entitlements, ad-hoc signing
- [x] Window with native titlebar/toolbar, 3 empty columns at 1:4:3, status bar
- [ ] `os_signpost` instrumentation scaffold

## M1 — Core navigation (fast)
- [x] `DirLister` via `getattrlistbulk` + benchmarks (10k / 100k / 1M)
- [x] `FileListView` custom-drawn list (cursor, icons per UTType, linemode column)
- [x] DirectoryService (Mutex-backed LRU, mtime-validated) + FSEvents watcher (reload keeps cursor by name)
- [x] KeyEngine (trie) + default keymap + yazi command parser, which-key popup, `keymap.toml` loading (manager context only)
- [x] Sorting (natural etc.), hidden toggle, history back/forward, scrolloff
- [~] keymap.toml loaded at window/tab creation (no hot reload yet); other settings live in UserDefaults + Settings window (⌘,)
- [x] Session restore: last folder, sort/hidden/dirs-first/linemode persisted (`Prefs`)

## M2 — Preview framework
- [ ] FMPluginKit protocols (Previewer, PreviewContent…) defined (needed by built-ins)
- [ ] TypeSniffer (UTType + magic), PreviewRouter, PreviewService (cancel + LRU)
- [x] Syntax highlighting for ~35 languages (own lexers; tree-sitter remains a later plugin)
- [~] Interim `QuickPreview` (image via ImageIO → UTF-8 text → QuickLook thumbnail → 4 KB hex) works. Still open: Previewer protocol, highlighter, virtualized hex, metadata header
- [ ] Previewers: PDF, Markdown, JSON/plist/structured, CSV, QuickLook fallback

## M3 — Media
- [~] Full viewer on Space (AVPlayerView + PDFKit + generic) with keys done. Still open: inline preview playback, own HUD
- [~] Image viewer: zoom (⌘+ ⌘− ⌘0, pinch), drag to pan, step through dir done. Still open: animated GIF
- [ ] Audio preview (artwork, tags, waveform)
- [ ] FFmpeg backend (CFFmpeg module map, VideoToolbox hwaccel, sample-buffer pipeline, A/V sync, subtitles)
- [ ] Dylib bundling script

## M4 — File operations
- [x] TaskCenter (background ops, per-item progress), `w` task list, status bar count, quit confirmation
- [x] yank/cut/paste (FileManager copy = APFS clone), trash (NSWorkspace.recycle), permanent delete (confirm), create, rename, symlink
- [~] Conflicts auto-rename `name_1.ext` (`P` overwrites) instead of a prompt; NSPasteboard interop (⌘C to Finder, Finder copy → `p`); open with (`O`). Still open: drag & drop with Finder

## M5 — Tabs, filter, search, jump
- [x] Tabs as native window tabs (ADR-017): `t` ⌘T, 1–9 ⌘1–9, `[` `]`, `{` `}`, ⌃c ⌘W; each tab has its own state
- [x] Find (`/` `?` `n` `N`, smart case, wraps), filter (`f`, live, Esc clears)
- [x] Recursive name search (`s` ⌘F; BFS walker over getattrlistbulk, streamed into a picker), content search (`S` ⇧⌘F; ripgrep, grep fallback)
- [x] Frecency (UserDefaults) + `z`, fuzzy `Z`

## M6 — Git, bookmarks, linemodes
- [~] Git status (porcelain v1 -z, off-main, refreshed on FS events) with M/A/?/D/R/U markers in all columns. Still open: branch in the status bar
- [x] Bookmarks (`b<c>` / `'<c>` / `''`), linemodes (`m*`)

## M7 — Plugins
- [ ] Loader, API versioning, safe mode, crash sentinel, timeouts
- [ ] `make plugin-sdk`, PluginTemplate, HelloPreviewer example

## M8 — Remaining previewers
- [ ] Archives (libarchive), SQLite, Mach-O, app bundles, fonts, 3D, dmg, certificates, symlink/alias, CSV polish
- [ ] Fixture suite asserting no "no preview" cases

## Later / ideas
- Bulk rename via $EDITOR, shell commands, open terminal here (deferred by ADR-009)
- Out-of-process XPC preview host for untrusted plugins
- tree-sitter highlighting plugin
- Rust hot-spot modules if profiling demands (ADR-012)

---

## Status / next step

**2026-11-01 (session 2):** M0 done and most of M1. Builds with no warnings, 8 tests pass, and the app runs:
3 columns, hjkl/arrows/gg/G/⌃d/⌃u, enter/leave/open, H/L history, space/⌃a/⌃r selection, `.` hidden,
`,x` sort, `mx` linemode, `g h/d/c`, `cc/cd/cf/cn` copy path, mouse click/double-click/wheel, live FSEvents
reload, and image/text/QL/hex preview.

Measured (M1 Pro, release, `make bench`): 10k entries list+sort cold **12 ms**, 100k **191 ms**
(getattrlistbulk 107 ms vs FileManager 440 ms; natural sort 73 ms). Cached lookups are ~0 ms.

**Session 2, later:** Space now opens the built-in viewer/player (ADR-013). Untested so far with real video
files through key input, because an agent can't inject keys; the user tests it manually.

**Session 2, later:** Video/audio previews now use AVFoundation (`QuickPreview.media`): a poster at 10% with
`W×H · duration · codec`, then QuickLook, then an info message. Media never falls back to hex (that was the bug:
when QuickLook failed, mp4s showed a hex dump). Columns can be resized by dragging the dividers; double-click
resets to 1:4:3. The ratio is saved in UserDefaults `fm.columnRatio` until filemaster.toml exists, at which point
the toml `ratio` becomes the default and the drag result still wins.

**Session 2, later:** Built-in syntax highlighter (`Sources/FMPreview/Syntax/SyntaxHighlighter.swift`):
hand-written lexers on UTF-16 (generic C-like/hash-comment code, HTML/XML with embedded JS/CSS, CSS/SCSS, JSON,
YAML, TOML/INI, Markdown, diff), detected by extension, filename and shebang. 256 KB tokenizes in 3 ms (release). Colors are in
`FMApp/PreviewHost/SyntaxTheme.swift` (Xcode-like, light/dark). Tests are in `Tests/FMPreviewTests`.
App icon: `scripts/make-icon.swift` (source of truth) → `Resources/AppIcon.icns` (`make icon`).

**Next (finish M1, then M2):**
1. Config: pick the TOML parser (ADR-010), load `filemaster.toml` and `keymap.toml`, hot reload.
2. Which-key popup for pending sequences (`KeyEngine.choices` already exists).
3. Session restore (last cwd, options).
4. Perf: 100k natural sort (73 ms). Try keying by `(firstBytes UInt64, full)` or radix prefix, and streaming the first batch.
5. M2: FMPluginKit protocols + PreviewRouter, replacing `FMPreview/QuickPreview.swift`.

**Known issues / notes:**
- `normalize()` uses `standardizingPath`, which turns `/private/tmp` into `/tmp`. FSEvents reports `/private/...`
  paths, so live reload does not fire inside /tmp. Fix: resolve the event paths, or `realpath` the watched roots.
- In a SwiftPM executable that depends on a target in the same package, that target is linked statically. For M7 the
  app must link `libFMPluginKit.dylib` dynamically (depend on the `.dynamic` product, or use the build script)
  so plugin bundles share one copy of the SDK types.
- Text preview uses NSTextView with non-selectable text (otherwise it would steal key focus). Revisit in M2.
- Verifying the UI from an agent session: build with `make app`, run the binary directly with a dir arg in the
  background, find the window ID with `CGWindowListCopyWindowInfo`, then `screencapture -l<id>`.
  `osascript` UI scripting has no accessibility permission, so keys can't be injected.
- Packaging (session 2, later): `make dist` → `dist/FileMaster-0.1.0.dmg` (1.2 MB, ad-hoc signed, hardened
  runtime; launch from the mounted DMG verified). It needs a Developer ID cert and a notarytool profile to be
  Gatekeeper-clean. See docs/DISTRIBUTION.md and ADR-015.
- Session 2, later: XML highlighting fixed for non-`.xml` names (content sniffing, more extensions), UTF-16/BOM text decoding,
  and the CRLF first-line split. Preview font is now bundled Fira Code at 13 pt, adjustable with ⌘+/⌘−/⌘0 (ADR-016). 19 tests pass.

- Session 2, later (big batch): all keys in KEYMAP.md now work. Added: file ops (M4), tabs/find/filter/search/jump (M5),
  git markers and bookmarks (M6), which-key, help (`~` F1), info (⌘I), Settings (⌘,), keymap.toml, session restore,
  viewer zoom (⌘+ ⌘− ⌘0, also ⌘* for Turkish keyboards), and keyboard divider resizing (⌃←/⌃→ left, ⌥←/⌥→ right).
  Custom-drawn views now redraw live during any resize. `l`/`→` only enter folders, never open files. Fixed the FSEvents
  /private/tmp mismatch. 25 tests pass.
- UI testing without Accessibility: debug builds replay `FM_SCRIPT` key steps (`App/ScriptDriver.swift`), then
  `screencapture -l<window id>` from outside. Example:
  `FM_SCRIPT='f|type:no|sleep:300' build/FileMaster.app/Contents/MacOS/FileMaster ~/dir`.
  Note: debug and release share UserDefaults (same bundle id), so scripted runs change `fm.lastFolder`/frecency. Clean
  up afterwards.

**Still not implemented (next candidates):**
1. M3 FFmpeg playback backend (AVFoundation-unplayable formats show a message for now) and inline video in the preview pane.
2. M7 plugin loader/SDK (FMPluginKit must become a dynamic library first).
3. Drag & drop with Finder; bulk rename via $EDITOR; shell commands (`;` `:`), deferred by ADR-009.
4. keymap.toml contexts other than `manager` (player/preview/input), hot reload; theme.toml.
5. Git branch in the status bar; M2 Previewer protocol/router; M8 extra previewers.
- Session 2, later: the viewer's `f` uses instant "fast full screen" (ADR-020); a full-screen viewer shows no toolbar or status bar.
  The debug ScriptDriver waits for a key window (it can't take keys while another instance is active). For agent tests, run the
  debug binary next to the user's app and screenshot by PID (scratch `widpid` helper) instead of `pkill`ing their app.
- Session 2, later: renamed to FileMaster (ADR-021). Installed at /Applications/FileMaster.app; DMG at dist/FileMaster-0.1.0.dmg.
