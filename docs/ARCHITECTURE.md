# Architecture

## 1. Repository layout (target)

```
FileMaster/
├── CLAUDE.md, README.md
├── docs/                      design docs (this folder)
├── Package.swift              SwiftPM manifest, platforms: [.macOS("27.0")]
├── Makefile                   app / run / test / plugin-sdk / clean
├── Sources/
│   ├── FMApp/                executable: NSApplication, windows, views, controllers
│   │   ├── App/               AppDelegate, menu, launch, safe mode
│   │   ├── Window/            BrowserWindowController, tab bar, toolbar, status bar
│   │   ├── Columns/           FileListView (custom-drawn), ColumnsController
│   │   ├── PreviewHost/       PreviewPaneController (hosts previewer views)
│   │   ├── Overlays/          which-key, input prompt, filter bar, task manager, help
│   │   └── Player/            full-window media viewer UI
│   ├── FMCore/               no AppKit. FS, model, ops, config, keymap engine
│   │   ├── FS/                DirLister (getattrlistbulk), FSWatcher (FSEvents), FileEntry
│   │   ├── Model/             DirectoryCache (LRU), TabState, Selection, History, Sorting
│   │   ├── Ops/               TaskQueue, CopyEngine (copyfile/clonefile), Trash, Conflicts
│   │   ├── Search/            parallel walker, filter, fuzzy matcher, frecency DB, bookmarks
│   │   ├── Git/               git status fetcher (porcelain v2)
│   │   ├── Keymap/            KeyEngine (trie), Action enum, keymap.toml loader
│   │   └── Config/            filemaster.toml, theme.toml, hot reload
│   ├── FMPreview/            built-in previewers + PreviewRouter + magic sniffing
│   ├── FMMedia/              MediaPlayer protocol, AVPlayer backend, FFmpeg backend
│   ├── CFFmpeg/               system-library target: module map → /opt/homebrew ffmpeg headers
│   └── FMPluginKit/          PUBLIC SDK, .dynamic, -enable-library-evolution
├── PluginsBuiltin/            first-party plugins shipped as real bundles (e.g. examples)
├── PluginTemplate/            SwiftPM package template for third-party plugins
├── Resources/                 Info.plist, FileMaster.entitlements, AppIcon, default *.toml
├── Tests/                     FMCoreTests, FMPreviewTests, perf tests (XCTMetric)
└── scripts/                   bundle-app.sh, bundle-dylibs.sh (FFmpeg rpath fixup), bench/
```

Dependency direction: `FMApp → FMPreview, FMMedia, FMCore, FMPluginKit`; `FMPreview → FMPluginKit, FMCore`;
`FMCore` does **not** depend on AppKit, so it can be unit-tested headless. `FMPluginKit` depends only on Foundation/AppKit/UTType.

## 2. Threading / concurrency model (Swift 6 strict)

| Context | Owns |
|---|---|
| `@MainActor` | all views, TabState mutation, cursor/selection, keymap dispatch. **Must never block.** |
| `DirectoryService` actor | DirectoryCache, listing requests (dedupes concurrent requests per path), FSWatcher fan-out |
| `PreviewService` actor | preview requests, cancellation, preview result LRU cache |
| `TaskQueue` actor | file operations; workers run on a dedicated concurrent pool (bounded, I/O-heavy) |
| Detached tasks (`.userInitiated`) | listing syscalls, decoding images, parsing files |
| `GitService`, `SearchService` actors | background subprocesses / walkers |

Rules:
- Cursor moves are synchronous on main: update index → redraw visible rows → **then** fire async preview request.
- Every async request carries a generation token. When the cursor moves, we cancel the in-flight `Task` and ignore stale
  results by token.
- Sendable value types (`FileEntry` is a struct with an interned name and packed attrs) cross actors. No class sharing.

## 3. Data flow: moving the cursor

```
keyDown → KeyEngine (trie) → Action.moveCursor(+1)
  → TabState.cursor += 1 (main)               ~µs
  → FileListView.setNeedsDisplay(rows changed) (main, next frame)
  → PreviewService.request(entry, gen)          (async)
       ├─ cache hit → deliver same frame
       └─ miss → PreviewRouter picks previewer → previewer.load() off-main
                   → result → main → PreviewPane swaps view (if gen still current)
  → Prefetch: listing of hovered dir (if dir), previews of cursor±2 (low priority)
```

## 4. Performance techniques

**Listing**
- `getattrlistbulk` with `ATTR_CMN_NAME | OBJTYPE | MODTIME | CRTIME | ACCESSMASK | FLAGS | FILEID`, `ATTR_FILE_DATALENGTH`, plus
  `ATTR_CMN_RETURNED_ATTRS`. Use a 256 KB buffer reused per thread. Symlinks are resolved lazily (only for the cursor row or a dir check).
- Huge directories (>20k entries) stream the first batch to the UI immediately, then sort incrementally as the rest arrives.
- Sorting: precompute sort keys once per listing (natural/numeric-aware keys via `CFStringTransform`-free custom comparator on
  UTF-8 bytes with case folding; `localizedStandardCompare` is too slow on 100k entries). Re-sorting is just a key swap.
- `DirectoryCache`: LRU of listings (default 64 dirs), invalidated by FSEvents. Going back to the parent is instant.
- FSEvents stream covers current, parent and preview directories; we restart it with new paths on navigation (cheap) using
  `kFSEventStreamCreateFlagFileEvents` with 50 ms latency. Changes are applied as diffs and the cursor stays on the same file.

**Rendering**
- `FileListView`: layer-backed, `wantsUpdateLayer` is not used; we use `draw(_:)` with dirty rects only. Each row's `CTLine` is cached by
  (entry id, width, theme). Icons are cached **per UTType** (plus per-file only for apps and custom icons, loaded lazily).
- No Auto Layout inside columns; frames are computed manually from the 1:4:3 ratios.
- Smooth 120 Hz scrolling and key repeat: the redraw is driven by `NSView.displayLink(target:selector:)` when animating.
- Text measurement uses a single fixed row height; widths are cached.

**Previews**
- Size caps: text reads the first 256 KB (configurable); hex uses virtualized rows over `mmap` with no cap (GB files are fine).
- Images use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = paneSize×scale` and
  `kCGImageSourceCreateThumbnailFromImageIfAbsent` (embedded thumbnails make big JPEGs/RAWs instant). Full decode only in the viewer.
- Thumbnail disk cache keyed by (inode, mtime, size, targetSize) in `~/Library/Caches/FileMaster/thumbs/`.
- Video: `AVAssetImageGenerator` poster at 10% of the duration, with metadata loaded via async `load(.duration, .tracks)`.

**Launch**
- Restore the last session's tabs. Draw the current dir first; parent and preview after. No plugin loading before the first frame
  (plugins load right after on a background queue, and their previewers become active once loaded).

## 5. Performance budgets (measure on M1 Pro, release build)

| Metric | Budget |
|---|---|
| Cold launch → first frame with listing | < 200 ms |
| List 10k-entry dir (uncached) | < 30 ms |
| List 100k-entry dir (first rows visible) | < 50 ms; full < 300 ms |
| Keypress → cursor redraw | < 4 ms (well under one 120 Hz frame) |
| Cached preview swap | < 8 ms |
| Uncached image preview (12 MP JPEG) | < 40 ms |
| Uncached text/code preview (256 KB) | < 25 ms |
| Idle memory | < 80 MB |

Benchmarks live in `Tests/Perf` (XCTest metrics) and `scripts/bench/` (synthetic dirs with 10k/100k/1M files).
Check signposts (`os_signpost`, subsystem `com.cem.filemaster`) in Instruments.

## 6. UI composition

```
┌ Window (unified toolbar: back/fwd · path breadcrumb · search field) ──────────────────────────┐
│ Tab bar: [1 ~/Projects] [2 ~/Downloads] …                                                    │
├───────────┬───────────────────────────────┬──────────────────────────────────────────────────┤
│ parent    │ current (cursor, selection,   │ preview pane: previewer view                     │
│ column    │ git markers, linemode column) │ (image / player / text / hex / table / QL …)     │
│  1        │  4                            │  3                                               │
├───────────┴───────────────────────────────┴──────────────────────────────────────────────────┤
│ status: NORMAL │ drwxr-xr-x │ 12.4 MB │ 2026-10-31 14:02 │ git:main │ tasks: 1 ▮▮▮▯ 63% │ 14/230 │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

Column dividers can be dragged (min 80 pt per column; double-click resets to 1:4:3; the ratio is persisted).

Overlays are floating panels inside the window: which-key, input prompt (rename/create/filter), task manager (`w`),
help (`~`), and the jump/fuzzy finder (`z`/`Z`). The full media viewer replaces the 3 columns while it's open (Esc returns).
Drag and drop to and from Finder works. ⌘C/⌘X/⌘V also write to the system `NSPasteboard` (file URLs) so it interoperates with Finder.

## 7. File operations

- `TaskQueue` actor: tasks are cancellable, show progress in the status bar and the `w` task manager, and run up to N concurrently
  (per-volume serialization for spinning or network disks).
- Copy: `clonefile(2)` on the same APFS volume (instant CoW). Otherwise `copyfile(3)` with `COPYFILE_ALL` and a progress callback.
- Move: `rename(2)` on the same volume; otherwise copy and then delete.
- Delete: `d` → Trash via `FileManager.trashItem` (undoable from Finder). `D` → permanent, with confirmation.
- Conflicts: the prompt offers overwrite / skip / rename (`name_1`) / apply-to-all.
- Rename (`r`) and create (`a`, a trailing `/` creates a directory) happen inline in the list.
