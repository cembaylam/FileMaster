# Preview system — "preview ALL files"

Goal: the right pane never shows "no preview". Every file gets the richest view we can produce quickly, and
unknown or binary files fall back to a fast, virtualized hex + strings view.

## 1. Pipeline

```
FileEntry ─► TypeSniffer ─► PreviewRouter ─► Previewer.makePreview(ctx) ─► PreviewContent
              (UTType from          (ranked previewers:     (async, cancellable,       (an NSView provider,
               extension + magic     plugins first, then     size-capped, off-main)     or a lightweight value
               bytes + xattrs)       built-ins by priority)                             rendered by host views)
```

- **TypeSniffer** finds the UTType from the extension, then checks the first 512 bytes against a magic table (ELF, Mach-O/fat,
  ZIP/JAR/APK/DOCX, gzip/xz/zstd/bz2, 7z, RAR, PDF, PNG/JPEG/GIF/WebP/HEIC/AVIF, SQLite, Matroska/WebM (EBML), RIFF (AVI/WAV), MP4
  `ftyp`, Ogg, FLAC, wasm, Java class, bplist, DMG koly trailer, font tables, …) and runs a text/binary check (UTF-8 validity
  plus the ratio of NUL bytes). Magic wins over a wrong extension.
- **PreviewRouter** matches each previewer's declared `UTType`s, magic and glob against the file. Precedence: user config override
  → plugin previewers → built-ins, by `priority`. If a previewer throws or times out (default 2 s), the next one is tried, with hex last.
- Every preview has a **header strip**: name, kind, size, permissions, owner, modified/created dates, plus Finder tags/xattrs
  (e.g. `com.apple.quarantine`) and the symlink target.
- Preview scrolling: `K`/`J` (yazi `seek`), mouse/trackpad. Results are cached in an LRU keyed by (inode, mtime, size, paneSize).

## 2. Built-in previewer catalog

| Kind | Detection | Implementation | Interactive |
|---|---|---|---|
| Directory | is dir | child listing via DirectoryService (same view as columns) | – |
| Image (JPEG/PNG/HEIC/HEIF/AVIF/WebP/TIFF/BMP/ICO/ICNS/PSD/TGA/EXR/RAW/DNG/JXL) | `public.image` | ImageIO thumbnail at pane size; EXIF summary | open in viewer (Enter) |
| Animated GIF/APNG/WebP | frame count > 1 | ImageIO frames → CALayer animation | yes |
| SVG | `public.svg-image` | NSImage (native SVG) → fallback WKWebView | – |
| Video | `public.movie` | poster frame + duration/codec/resolution/bitrate; **inline playback** in the pane (muted autoplay configurable) | Enter → full player |
| Audio | `public.audio` | artwork + tags + waveform (Accelerate-downsampled) | inline play |
| PDF | `com.adobe.pdf` | PDFKit `PDFView` (first page instantly, scrollable) | scroll pages |
| Text / source code | conforms to `public.text` or sniffed as text | encoding detection, first 256 KB, syntax highlighting (own fast tokenizer per language family; tree-sitter later as a plugin) | – |
| Markdown | `.md` | rendered (`AttributedString(markdown:)` + styles); toggle raw | – |
| JSON / YAML / TOML / XML / plist | ext/magic | pretty-printed + highlighted; binary plist decoded | – |
| CSV / TSV | ext | table view (first 1000 rows) | – |
| Archives (zip, tar, gz, bz2, xz, zst, 7z, rar, iso, cpio, jar, apk, ipa, xip) | magic | content listing via libarchive (system `libarchive.2.dylib` + our module map, or brew libarchive) | – |
| SQLite | magic `SQLite format 3` | tables + schema + row counts, first rows (system `libsqlite3`, read-only, `immutable=1`) | – |
| Mach-O / dylib / executable | magic | archs, min OS, load commands, linked libs, entitlements, code signature summary (Security.framework `SecStaticCode`) | – |
| App / bundle (.app, .framework, .bundle) | is package | icon, Info.plist summary, version, signature | `l` enters as dir |
| Fonts (ttf/otf/ttc/woff/woff2) | `public.font` | CoreText sample sheet + font metadata | – |
| 3D (usdz, usd, obj, stl, ply, dae, scn, glTF via plugin) | ext | SceneKit/RealityKit view, auto-rotate | orbit |
| Office / iWork / RTF / Pages / Numbers / Keynote / eml / vcf / ics | QuickLook supports | `QLPreviewView` (Quartz) embedded | scroll |
| Disk image (dmg/sparseimage) | magic | `hdiutil imageinfo -plist` summary | – |
| Certificates / keys (cer, pem, p12 public part, mobileprovision) | ext/magic | Security.framework decode → summary | – |
| Symlink / Finder alias | lstat / bookmark data | target path + status (broken?) + preview of the target | – |
| Empty file | size 0 | "empty file" + metadata | – |
| **Anything else / binary** | fallback | **hex view** (virtualized over mmap, offset · hex · ASCII; any size) + "Strings" tab + detected magic description | jump to offset |

The QuickLook fallback goes before hex: if `QLPreviewView` can render the type (the system has a QL generator for it), use it.
Otherwise use hex.

## 3. Previewer protocol (shared with plugins)

Built-in previewers conform to `FMPluginKit.Previewer` (see PLUGINS.md), which keeps the plugin API honest.
Requirements: `makePreview` must check `Task.isCancelled` / `ctx.isCancelled` often, must not touch AppKit except to
create the returned view on main, and must respect `ctx.maxBytes`.

## 4. Tests

There's a fixture folder `Tests/Fixtures/preview/` with one sample per type (generated by `scripts/make-fixtures.sh` where possible).
A test asserts that every fixture gets routed to the expected previewer and that none ends up "no preview".

### Text decoding and language detection (details)
- Decoding: a UTF-16 LE/BE file with a BOM is decoded as UTF-16. A UTF-8 BOM is stripped. Otherwise the text must be valid UTF-8 with
  no NUL in the first 8 KB.
- Language is chosen by file name, then extension, then shebang, then **content sniffing** on the first line: `<?xml`,
  `<!DOCTYPE`, `<svg`, `<plist`, `<!--` → XML, and `<!DOCTYPE html`/`<html` → HTML. Sniffing covers XML with
  ambiguous extensions (`*.config`, `*.manifest`), which are intentionally left out of the extension map.
- The first line is split with `Character.isNewline`, because CRLF is one Swift `Character`.
- In XML/HTML, `<?…`/`<!…` names are colored as `meta`.
