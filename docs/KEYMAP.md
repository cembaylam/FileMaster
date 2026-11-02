# Keymap

These defaults mirror yazi's keymap (ADR-008). Arrow keys and standard ⌘ shortcuts work too. Everything can be overridden in
`~/.config/filemaster/keymap.toml`. Multi-key sequences show a which-key popup after 300 ms.

## Navigation

| Keys | Action |
|---|---|
| `k` `↑` / `j` `↓` | cursor up / down |
| `h` `←` | go to parent |
| `l` `→` | enter dir (files: nothing; use `Space` to preview, `Enter`/`o` to open) |
| `gg` / `G` | top / bottom |
| `⌃u` / `⌃d` | half page up / down |
| `⌃b` `PgUp` / `⌃f` `PgDn` | page up / down |
| `H` / `L` (`⌘[` / `⌘]`) | history back / forward |
| `K` / `J` | scroll preview up / down |
| `gh` `gc` `gd` `g␣` | go home / config / Downloads / prompt for path (`⌘L` / `⌘⇧G` too) |
| `⌘↑` / `⌘↓` | parent / open (Finder style) |
| `⌘+` / `⌘−` / `⌘0` | zoom in / out / reset. Viewer open: PDF or image zoom; otherwise preview text size (`⌘=` and `⌘*` also zoom in) |
| `⌃←` / `⌃→` | move the left column divider (macOS uses these for Spaces by default; turn that off in System Settings → Keyboard → Shortcuts → Mission Control) |
| `⌥←` / `⌥→` | move the right column divider |

## Selection

| Keys | Action |
|---|---|
| `space` | open the built-in viewer/player (ADR-013) |
| `Tab` | toggle select, then move down |
| `v` / `V` | visual select / visual unselect mode |
| `⌃a` (`⌘A`) | select all |
| `⌃r` | invert selection |
| `Esc` | clear selection / cancel mode / close overlay |

## File operations

| Keys | Action |
|---|---|
| `o` `Enter` | open with the default app (dirs: enter) |
| `O` | open with… (interactive list of apps and plugin openers) |
| `y` (`⌘C`) | yank (copy) |
| `x` (`⌘X`) | yank (cut) |
| `p` (`⌘V`) | paste |
| `P` | paste, overwriting |
| `Y` / `X` | cancel yank |
| `d` (`⌘⌫`) | move to Trash |
| `D` (`⌘⌥⌫`) | delete permanently (confirm) |
| `a` (`⌘⇧N`) | create file; name ending in `/` creates a directory |
| `r` (`F2`) | rename (cursor before the extension) |
| `-` | symlink the yanked files here |
| `.` (`⌘⇧.`) | toggle hidden files |
| `cc` `cd` `cf` `cn` | copy path / dir path / filename / name without ext |
| `w` | task list (background file operations) |
| `⌘I` | info (size of folders computed in the background; Return copies a value) |
| `;` `:` | *(reserved: shell, deferred per ADR-009)* |

## Find / search / jump

| Keys | Action |
|---|---|
| `/` `?` | find next / previous (incremental) |
| `n` / `N` | next / previous match |
| `f` | filter the current dir (live) |
| `s` (`⌘F`) | recursive name search (parallel walker, fd-like) |
| `S` | content search (ripgrep if present, else built-in) |
| `z` | frecent jump (zoxide-like) |
| `Z` | fuzzy find in the subtree |
| `b<char>` | set bookmark |
| `'<char>` | jump to bookmark (`''` = list) |

## Sort & linemode

`,m` mtime · `,b` birth time · `,e` extension · `,a` alphabetical · `,n` natural · `,s` size. Uppercase reverses (`,M`).
`,d` toggles dirs first.
Linemode: `ms` size · `mp` permissions · `mb` btime · `mm` mtime · `mo` owner · `mn` none.

## Tabs

| Keys | Action |
|---|---|
| `t` (`⌘T`) | new tab at cwd |
| `1`…`9` (`⌘1`…`⌘9`) | switch to tab |
| `[` / `]` (`⌃⇥` / `⌃⇧⇥`) | previous / next tab |
| `{` / `}` | swap tab left / right |
| `⌃c` (`⌘W`) | close tab |

## App

`~` / `F1` help (searchable keymap) · `q` quit (confirms if tasks are running) · `⌘,` settings · `⌘I` info panel.

## keymap.toml format

```toml
# prepend/append extend the defaults; [[keymap]] replaces them entirely (like yazi)
[[manager.prepend_keymap]]
on   = ["g", "p"]
run  = "cd ~/Projects"
desc = "Go to Projects"

[[manager.prepend_keymap]]
on   = "<C-p>"
run  = "plugin com.example.hello.greet"

# contexts: manager, preview, player, input, overlay
[[player.prepend_keymap]]
on  = "<S-Right>"
run = "seek 60"
```
Key syntax: `<C-x>` ctrl, `<S-x>` shift, `<A-x>` option, `<D-x>` command, `<Space>`, `<Enter>`, `<Esc>`, `<Up>`…
