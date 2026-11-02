# Architecture Decision Records

Format: each ADR has an ID, date, status, the decision, and why. To change a decision, add a new ADR that
supersedes the old one; don't edit history.

---

## ADR-001 — Platform: macOS 27+, arm64 only
*2026-11-01 · Accepted*

Supports only the current OS and Apple Silicon (dev machine: M1 Pro, macOS 27.2, Xcode 27.2, Swift 6.4).
**Why:** the user asked for no back-compat. This lets us use the newest AppKit, AVFoundation, Swift concurrency
and ImageIO APIs without availability checks, and lets us tune for arm64 (NEON/Accelerate, VideoToolbox, unified memory).

## ADR-002 — UI: AppKit for the hot path, SwiftUI only for cold UI
*2026-11-01 · Accepted*

The window, the column views, the preview host and the player are AppKit. The file list is a **custom layer-backed
NSView** that draws only the visible rows, with fixed row height, cached Core Text lines, and no Auto Layout inside
the list. Settings, the about window and simple dialogs may use SwiftUI.
**Why:** the user wants it "very very fast". NSTableView and SwiftUI List add per-row view overhead and layout passes.
yazi-style dense lists with key repeat at 120 Hz need roughly <2 ms per redraw. If the custom view turns out
not to be worth it, `NSTableView` (cell reuse, fixed height) is the fallback.

## ADR-003 — Look: native chrome, yazi layout
*2026-11-01 · Accepted*

A real macOS window: unified translucent titlebar and toolbar, native tabs or tab bar, system font
(SF Pro, SF Mono for hex and code), system accent and selection colors, follows light/dark mode. The content area
is yazi's 3-column layout with default ratio **1 : 4 : 3** (parent : current : preview), dense rows, and a status bar
at the bottom like yazi's (mode, permissions, size, position `n/N`, task progress).

## ADR-004 — Distribution: personal / Developer ID, no sandbox
*2026-11-01 · Accepted*

App Sandbox is off. Hardened runtime is on, with entitlements:
`com.apple.security.cs.disable-library-validation` (load third-party plugin dylibs) and
`com.apple.security.cs.allow-jit` (not needed now; add it only if something requires it). Signing is ad-hoc (`codesign -s -`)
during development, Developer ID later if needed. The user should grant Full Disk Access in System Settings for full coverage.
**Why:** a sandboxed file manager has to go through security-scoped bookmarks everywhere and can't run external
tools or load plugins freely. ForkLift and Path Finder ship unsandboxed for the same reason.

## ADR-005 — Build system: SwiftPM + Makefile, no Xcode project
*2026-11-01 · Accepted*

`Package.swift` defines all modules. `make app` assembles `FileMaster.app` (Info.plist, entitlements, resources,
`Contents/Frameworks/libFMPluginKit.dylib`, bundled FFmpeg dylibs, and the built-in `Contents/PlugIns`)
and signs it.
**Why:** this is fully reproducible from the CLI across sessions and there are no pbxproj merge headaches. Xcode can still open
`Package.swift` for debugging and Instruments. If we hit a limit (asset catalogs, etc.), revisit with XcodeGen.

## ADR-006 — Plugins: native Swift bundles against a stable SDK
*2026-11-01 · Accepted (user choice)*

Plugins are `.fmplugin` bundles (an NSBundle containing a Swift dylib) loaded in-process at runtime. They link against
`FMPluginKit`, a **dynamic library built with `-enable-library-evolution`** so that its ABI stays stable across app
updates. Details are in `docs/PLUGINS.md`.
**Why (user):** native speed and full API power.
**Known costs and mitigations:** a crash in a plugin takes down the app. To limit that, a crash sentinel auto-disables
the offending plugin on the next launch, holding ⌥ at launch or passing `--safe-mode` disables all plugins,
and plugins run under per-call timeouts and cancellation. Later, an optional XPC preview host could run untrusted previewers
out-of-process (ADR to be written if we do it).
Built-in previewers implement the **same protocols** (dogfooding), but they're compiled into the app.

## ADR-007 — Media: AVFoundation first, FFmpeg fallback
*2026-11-01 · Accepted*

Anything AVFoundation can open (mp4/mov/m4v/HEVC/ProRes/AAC/ALAC/MP3/WAV/FLAC…) plays through `AVPlayer`
(hardware decode, lowest power). For containers or codecs it can't handle (MKV, WebM, AVI, FLV, OGG/Opus, VP8/VP9 in some
containers, WMV…), we use our own pipeline: FFmpeg `libavformat` demux → decode (VideoToolbox hwaccel for H.264/HEVC/VP9/ProRes,
software for the rest, e.g. dav1d for AV1, since M1 has no AV1 hardware decode) → `CVPixelBuffer` →
`AVSampleBufferDisplayLayer` + `AVSampleBufferAudioRenderer`, synced by `AVSampleBufferRenderSynchronizer`.
Both pipelines sit behind one `MediaPlayer` protocol and one player UI. Details are in `docs/MEDIA.md`.
**Why not libmpv:** its render API is OpenGL-based on macOS, while our own pipeline stays Metal/CoreAnimation-native and
shares UI and controls with AVPlayer. Fast-path idea: for MKV holding H.264/HEVC + AAC, remux on the fly into fragmented MP4 and
hand it to AVPlayer.
**Licensing:** brew's FFmpeg is a GPL build. That's fine for personal use; if we ever distribute, switch to an LGPL build.

## ADR-008 — Keyboard: yazi defaults + arrows + ⌘ shortcuts, user-remappable
*2026-11-01 · Accepted*

Keybindings follow yazi's default keymap, plus arrow keys and standard macOS ⌘ shortcuts. Everything can be remapped
in `keymap.toml`. Multi-key sequences (`gg`, `,m`, `cc`) go through a small trie-based key engine with a which-key popup.
See `docs/KEYMAP.md`.

## ADR-009 — v1 scope
*2026-11-01 · Accepted*

In v1: core navigation, previews for all file types, image and video player, plugin loading, **file ops** (task queue),
**tabs + filter + search + jump**, **git status + bookmarks + frecency**.
Deferred (not in v1): bulk rename via $EDITOR, shell command execution (`;` / `:`), open-terminal-here.
The keys for those stay reserved in the keymap.

## ADR-010 — Config: TOML in `~/.config/filemaster/`, state in Application Support
*2026-11-01 · Accepted*

User-editable config goes in `~/.config/filemaster/{filemaster,keymap,theme}.toml` (yazi-like, dotfile-friendly). It's hot-reloaded on change.
Caches (thumbnails, listing snapshots) go in `~/Library/Caches/FileMaster/`. State (frecency DB, bookmarks, session/tabs, plugin
crash sentinel) goes in `~/Library/Application Support/FileMaster/`. The TOML parser should be a small pure-Swift dependency
(e.g. `TOMLDecoder`) or our own subset parser; pick one at M1.

## ADR-011 — Filesystem access: BSD syscalls, not FileManager, on the hot path
*2026-11-01 · Accepted*

Directory listing uses `getattrlistbulk(2)`, which returns names plus all needed attributes in bulk with one syscall per batch.
File watching uses FSEvents (per-window stream on the visible directories) with a `DispatchSource` vnode fallback. File reads
for previews use `mmap` with a size cap. `FileManager` and `URL.resourceValues` are allowed only on cold paths.
**Why:** `contentsOfDirectory` + `resourceValues` costs an order of magnitude more per entry.

## ADR-012 — Language: Swift for the app; Rust only for profiled hot spots
*2026-11-01 · Accepted*

The user allowed Rust anywhere. We still chose **Swift 6.4** for the whole app.
**Why:** the speed-critical work is syscalls (`getattrlistbulk`, mmap, FSEvents) and Apple frameworks (AppKit/CoreAnimation,
ImageIO, VideoToolbox, AVFoundation, PDFKit, QuickLook). Swift calls these directly, while Rust would need FFI glue on both
sides and gives no speedup for them. Plugins are native Swift bundles (ADR-006), so a Swift core keeps the SDK natural.
**Escape hatch:** if Instruments shows a CPU-bound hot spot that Swift handles poorly (candidates: recursive content search
like ripgrep's `grep-searcher` + `ignore` crates, a fuzzy matcher, or a big-file syntax tokenizer), we build it as a Rust
`staticlib` with a C ABI (`cbindgen` header + SwiftPM system-library module map), driven by `make`. Rust isn't installed
yet (`brew install rustup` when needed). Any such module needs its own ADR.

## ADR-013 — Space opens the built-in viewer; selection moves to Tab
*2026-11-01 · Accepted (user request)*

`Space` opens the app's own full viewer/player for the file under the cursor (not macOS Quick Look, and not
yazi's toggle-select). Toggle-select moves to `Tab`. Viewer behaviour, per the user: `0`–`9` seek to 0–90%
(YouTube-style), `f`/`F` toggles fullscreen, and the first `Esc` leaves fullscreen while the next one closes the viewer.
For now the viewer uses AVKit's `AVPlayerView` (floating native controls). M3 replaces it with our own HUD and the
FFmpeg fallback behind the `MediaPlayer` protocol.

## ADR-014 — Own syntax lexers; icon rendered from code
*2026-11-01 · Accepted*

Syntax highlighting uses small hand-written lexers (one generic configurable code lexer plus dedicated markup/CSS/
data-format lexers) instead of tree-sitter or a JS highlighter. **Why:** zero dependencies and ~3 ms per 256 KB, and
preview only needs approximate, fast coloring. tree-sitter can come later as a plugin for precise highlighting.
The app icon is drawn by `scripts/make-icon.swift` with CoreGraphics (squircle on Apple's 824/1024 grid, folder
with the 1:4:3 columns, accent cursor row, and a play glyph), so it stays editable and crisp at every size.

## ADR-015 — Distribution: DMG, Developer ID + notarization, ad-hoc fallback
*2026-11-01 · Accepted*

`make dist` builds a signed, LZFSE-compressed DMG (app + /Applications link) outside the App Store, matching the
no-sandbox design (ADR-004). With a Developer ID identity and a notarytool profile it signs with a secure
timestamp, then notarizes and staples. Without them it falls back to ad-hoc signing, so packaging never blocks on
credentials. We chose DMG over zip/pkg: drag-to-install, signable and staplable, no installer scripts.
Details: docs/DISTRIBUTION.md.

## ADR-016 — Preview text font: bundled Fira Code, adjustable size
*2026-11-01 · Accepted*

At the user's request, text/hex previews use **Fira Code**, 13 pt by default (it was 11 pt SF Mono). The Regular and SemiBold
TTFs plus the OFL license ship in `Resources/Fonts`, which the bundle copies to `Contents/Resources/Fonts`. They are
registered with `ATSApplicationFontsPath`, so the app looks the same on Macs without the font installed (the OFL allows
bundling). If the font can't load, previews fall back to SF Mono. View → Bigger/Smaller/Actual Size (⌘+ ⌘− ⌘0) changes the size
(9–28 pt), which is saved in UserDefaults `fm.previewFontSize`. Code: `FMApp/PreviewHost/PreviewFont.swift`. Fira Code has
no italic, so comments are distinguished by color only.

## ADR-017 — Tabs are native window tabs
*2026-11-01 · Accepted*

Each tab is a `BrowserWindowController` window in an `NSWindowTabGroup` (`addTabbedWindow`). We don't use an in-view tab
model. This gives us the native tab bar, ⌃⇥, drag-out-to-window and per-tab state (one `BrowserViewController` each)
for free. yazi keys map onto the group: `1`–`9` select `tabbedWindows[i]`, `{`/`}` swap via `removeWindow` +
`insertWindow(at:)`. The yank register (`BrowserViewController.yanked`) is static, so it is shared across tabs and windows like yazi's.

## ADR-018 — Overlays: one prompt bar, one picker
*2026-11-01 · Accepted*

Text input (rename, create, find, filter, go to) uses a single `PromptView` above the status bar. Every list-to-choose-from
(open with, help, bookmarks, search results, z/Z, tasks, info) uses a single `PickerView`, a command palette with fuzzy
filtering (`Fuzzy`), off-main filtering above 3k items, and streaming `appendItems`. Search results are revealed with
cd + focus, not shown as a virtual directory (yazi's approach), which keeps `DirState` simple. Paste conflicts are
auto-renamed `name_1.ext` (yazi behavior) with `P` to overwrite, not a modal prompt. Trash needs no confirmation
(it is reversible, the Finder convention). Permanent delete always confirms.

## ADR-019 — Debug key-script driver for UI verification
*2026-11-01 · Accepted*

Agent sessions have no Accessibility permission, so they can't send keystrokes to the app. Debug builds read `FM_SCRIPT` and
synthesize NSEvents in-process (`ScriptDriver`, compiled out of release). Screenshots come from `screencapture -l`.

## ADR-020 — Viewer full screen is "fast" (non-native), not macOS full screen
*2026-11-01 · Accepted*

The user wanted full screen to be instant. macOS native full screen animates into a new Space (~0.7 s) and can't be
sped up. So the viewer's `f` reparents the ViewerView into a borderless, screen-sized window and hides the menu bar and Dock,
the same "non-native full screen" approach as IINA and mpv. Trade-offs: it gets no Space of its own (Mission Control doesn't
show it as a separate desktop) and it doesn't swipe between Spaces. The browser window keeps native full screen (green button).

## ADR-021 — Renamed to FileMaster
*2026-11-01 · Accepted*

The app is now **FileMaster** (bundle id `com.cem.filemaster`). The old name is obsolete everywhere: module prefix `OFM` → `FM`
(`FMCore`, `FMPreview`, `FMApp`, `FMPluginKit`), `fm-bench`, UserDefaults keys `fm.*`, config dir `~/.config/filemaster/`,
plugin extension `.fmplugin`, debug env `FM_SCRIPT`. Earlier ADRs were updated in place for the names only. The existing
settings were copied once to the new domain with a shell step (no migration code in the app).
