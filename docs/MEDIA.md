# Media: image viewer & video/audio player

See ADR-007. There's one `MediaPlayer` protocol and two backends, behind a single UI.

## 1. Where media shows up

1. **Preview pane (inline):** images render instantly. Video shows the poster; with `preview.video_autoplay = "muted"` (default:
   `"off"`, poster only) it plays inline. Audio shows artwork, tags and a waveform.
2. **Full viewer (Space on any file):** replaces the column area in the same window (Esc/q/Space returns to the exact cursor).
   Video/audio go to AVPlayer, PDF to PDFKit, and everything else to the preview renderer at full size. `j/k`/`n/p` step through
   the files in the directory. Implemented in `Sources/FMApp/Player/ViewerView.swift`, with keys in
   `BrowserViewController.handleViewerKey`.

## 2. Backends

```swift
protocol MediaPlayer: AnyObject {
    var layer: CALayer { get }            // AVPlayerLayer or AVSampleBufferDisplayLayer
    var duration: Duration? { get }
    var currentTime: Duration { get }
    var rate: Float { get set }
    var volume: Float { get set }
    var tracks: MediaTracks { get }       // audio/subtitle selection
    func play(); func pause()
    func seek(to: Duration, exact: Bool) async
    func stepFrame(_ delta: Int)
}
```

- **AVPlayerBackend:** `AVURLAsset` → `AVPlayerItem` → `AVPlayer` + `AVPlayerLayer`. We check `asset.load(.isPlayable)` and the
  track formats. If it's not playable, we fall through to FFmpeg.
- **FFmpegBackend** (module `CFFmpeg`, links `/opt/homebrew/opt/ffmpeg/lib`):
  - demux thread: `avformat_open_input` → packet queues per stream
  - video decode: `AV_HWDEVICE_TYPE_VIDEOTOOLBOX` hwaccel → `CVPixelBuffer` (zero-copy) → `CMSampleBuffer` →
    `AVSampleBufferDisplayLayer`; software decode (AV1, VP8, etc.) → `sws_scale` into an IOSurface-backed pixel buffer pool
  - audio decode → `swr_convert` to Float32 interleaved → `CMSampleBuffer` → `AVSampleBufferAudioRenderer`
  - clock: `AVSampleBufferRenderSynchronizer` (handles A/V sync, rate, pause)
  - subtitles: SRT/ASS text tracks rendered by a CATextLayer overlay (ASS styling: basic only in v1)
  - Fast path (optional later): MKV with H.264/HEVC + AAC/AC3 → remux to fMP4 in memory (`AVAssetResourceLoader`) → AVPlayer.
- **Bundling:** `scripts/bundle-dylibs.sh` copies libav*/libsw* and their transitive brew deps into `Contents/Frameworks`
  and rewrites install names to `@rpath` (`install_name_tool`), then re-signs.

## 3. Player controls (player focused)

| Key | Action |
|---|---|
| `space` | play / pause (non-media: close viewer) |
| `0`…`9` | jump to 0%…90% of the duration (YouTube-style) |
| `←` / `→` | seek −10 s / +10 s (YouTube-style); `H`/`L` or ⇧←/⇧→: ±30 s |
| `↑` / `↓` | volume ±5% |
| `m` | mute |
| `,` / `.` | frame step back / forward (paused) |
| `j`/`n` · `k`/`p` | next / previous file |
| `↑` / `↓`, `PgUp` / `PgDn` | PDF and text/hex: scroll (40 pt / a page). Images: previous / next file |
| `J` / `K` | PDF next/prev page; scroll text |
| `[` / `]` | speed −/+ 0.25× ; `=` reset |
| `a` / `s` | cycle audio / subtitle track |
| `f` / `F` | toggle fullscreen |
| `i` | toggle info overlay (codec, fps, decoder hw/sw, dropped frames) |
| `Esc` | exit fullscreen if fullscreen, otherwise close the viewer |
| `q` | close the viewer (also leaves fullscreen if the viewer entered it) |

The UI overlay is an auto-hiding HUD (NSVisualEffectView) with a scrubber and thumbnail hover via `AVAssetImageGenerator`
(or FFmpeg keyframe seek).

### Viewer zoom (session 2)
`⌘+` / `⌘=` / `⌘*` zoom in, `⌘−` zooms out, `⌘0` fits. PDF uses PDFKit `zoomIn`/`zoomOut`/`autoScales`. Images scale a
sublayer around the center (1×–32×), with drag to pan and trackpad pinch. Text/hex changes the preview font size. Video: no zoom.
Outside the viewer the same keys change the preview text size (`BrowserView.zoom`).

### Full screen (session 2)
`f` in the viewer uses **fast full screen** (`Player/FastFullScreen.swift`, ADR-020). The viewer view moves into a borderless
window covering the screen, with menu bar and Dock hidden through `NSApp.presentationOptions`. The picture sits below the
notch and the strip above stays black. Toggling is instant. `f` or `Esc` returns; `q`/`Space` exits and closes the viewer.
Keys typed in the full-screen window are forwarded to the BrowserView. AVKit's own full-screen button is hidden because it uses
the slow native transition. If the window is already in native full screen (green button, ⌃⌘F) and the viewer is open,
the toolbar and status bar are hidden too (`updateChrome`).
