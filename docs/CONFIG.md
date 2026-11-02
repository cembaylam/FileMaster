# Configuration

See ADR-010. Changes to these files are hot-reloaded (FSEvents watch on `~/.config/filemaster/`).

| Path | Purpose |
|---|---|
| `~/.config/filemaster/filemaster.toml` | general settings |
| `~/.config/filemaster/keymap.toml` | key overrides (KEYMAP.md) |
| `~/.config/filemaster/theme.toml` | colors and icons (defaults to system colors) |
| `~/.config/filemaster/plugins/` | user plugin bundles |
| `~/Library/Application Support/FileMaster/` | `state.json` (tabs/session), `frecency.db`, `bookmarks.json`, `plugin-sentinel`, `Plugins/` |
| `~/Library/Caches/FileMaster/thumbs/` | thumbnail disk cache (size-capped LRU, default 1 GB) |

## filemaster.toml (defaults)

```toml
[manager]
ratio          = [1, 4, 3]
show_hidden    = false
sort_by        = "natural"     # natural|alphabetical|mtime|btime|extension|size
sort_reverse   = false
sort_dir_first = true
linemode       = "size"        # none|size|permissions|mtime|btime|owner
scrolloff      = 5
row_height     = 22            # points

[preview]
max_text_bytes    = 262144
video_autoplay    = "off"      # off|muted|on
timeout_ms        = 2000
image_quality     = "fit"      # fit|fill
hex_bytes_per_row = 16
quicklook_fallback = true

[opener]
# per-UTType or glob overrides, e.g.
# "public.source-code" = "com.microsoft.VSCode"

[tasks]
max_concurrent = 4

[search]
content_tool = "auto"          # auto (rg if found) | builtin

[git]
enabled = true

[plugins]
safe_mode = false
# [plugins."com.example.hello"]
# enabled = true
```
