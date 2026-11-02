/// Default bindings, mirroring yazi's keymap plus arrows (docs/KEYMAP.md). ⌘-shortcuts that have a menu
/// item (⌘[ ⌘] ⌘⇧. …) live in the main menu instead.
public enum DefaultKeymap {
    public static let manager: [KeyBinding] = {
        var b: [KeyBinding] = []
        func bind(_ keys: [String], _ run: String, _ desc: String) {
            for k in keys {
                b.append(KeyBinding(on: k, run: run, desc: desc)!)
            }
        }
        // Navigation
        bind(["k", "<Up>"], "arrow -1", "Move up")
        bind(["j", "<Down>"], "arrow 1", "Move down")
        bind(["<C-u>", "<S-Up>"], "arrow -50%", "Half page up")
        bind(["<C-d>", "<S-Down>"], "arrow 50%", "Half page down")
        bind(["<C-b>", "<PageUp>"], "arrow -100%", "Page up")
        bind(["<C-f>", "<PageDown>"], "arrow 100%", "Page down")
        bind(["g g", "<Home>"], "arrow top", "Top")
        bind(["G", "<End>"], "arrow bot", "Bottom")
        bind(["h", "<Left>", "<D-Up>", "<Backspace>"], "leave", "Parent directory")
        bind(["l", "<Right>"], "enter", "Enter directory")
        bind(["o", "<Enter>", "<D-Down>"], "open", "Open")
        bind(["H"], "back", "History back")
        bind(["L"], "forward", "History forward")
        bind(["K"], "seek -5", "Scroll preview up")
        bind(["J"], "seek 5", "Scroll preview down")
        // Selection
        bind(["<Space>"], "view", "Open in built-in viewer / player")
        bind(["<Tab>"], "toggle", "Toggle selection")
        bind(["<C-a>"], "toggle_all --state=on", "Select all")
        bind(["<C-r>"], "toggle_all", "Invert selection")
        bind(["<Esc>"], "escape", "Exit visual / clear selection / filter / find")
        bind(["v"], "visual_mode", "Visual select mode")
        bind(["V"], "visual_mode --unset", "Visual unselect mode")
        // View
        bind(["."], "hidden", "Toggle hidden files")
        for (k, by) in [("m", "modified"), ("b", "created"), ("e", "extension"), ("a", "alphabetical"),
                        ("n", "natural"), ("s", "size")] {
            bind([", \(k)"], "sort \(by)", "Sort by \(by)")
            bind([", \(k.uppercased())"], "sort \(by) --reverse", "Sort by \(by) (reverse)")
        }
        bind([", d"], "dir_first", "Toggle directories first")
        for (k, mode) in [("s", "size"), ("p", "permissions"), ("b", "btime"), ("m", "mtime"), ("o", "owner"), ("n", "none")] {
            bind(["m \(k)"], "linemode \(mode)", "Linemode: \(mode)")
        }
        // Goto
        bind(["g h"], "cd ~", "Go home")
        bind(["g c"], "cd ~/.config/filemaster", "Go to config")
        bind(["g d"], "cd ~/Downloads", "Go to Downloads")
        bind(["g <Space>"], "cd_interactive", "Go to path…")
        // Copy paths
        bind(["c c"], "copy path", "Copy path")
        bind(["c d"], "copy dir", "Copy directory path")
        bind(["c f"], "copy filename", "Copy filename")
        bind(["c n"], "copy name_without_ext", "Copy name without extension")
        // File operations (⌘ variants are menu items)
        bind(["O"], "open_with", "Open with…")
        bind(["y"], "yank", "Yank (copy)")
        bind(["x"], "yank --cut", "Yank (cut)")
        bind(["p"], "paste", "Paste")
        bind(["P"], "paste --force", "Paste (overwrite)")
        bind(["Y", "X"], "unyank", "Cancel yank")
        bind(["-"], "link", "Symlink yanked files here")
        bind(["d"], "remove", "Move to Trash")
        bind(["D"], "remove --permanently", "Delete permanently")
        bind(["a"], "create", "Create file (end with / for folder)")
        bind(["r", "<F2>"], "rename", "Rename")
        bind(["w"], "tasks_show", "Tasks")
        // Find / search / jump
        bind(["/"], "find", "Find next")
        bind(["?"], "find --previous", "Find previous")
        bind(["n"], "find_arrow", "Next match")
        bind(["N"], "find_arrow --previous", "Previous match")
        bind(["f"], "filter", "Filter")
        bind(["s"], "search fd", "Search names (recursive)")
        bind(["S"], "search rg", "Search contents (ripgrep)")
        bind(["z"], "jump zoxide", "Jump to a recent folder")
        bind(["Z"], "jump fzf", "Fuzzy find in subtree")
        // Bookmarks: b<char> set, '<char> jump, '' list
        for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            bind(["b \(c)"], "mark set \(c)", "Set bookmark \(c)")
            bind(["' \(c)"], "mark jump \(c)", "Jump to bookmark \(c)")
        }
        bind(["' '"], "mark --list", "List bookmarks")
        // Tabs
        bind(["t"], "tab_create --current", "New tab")
        for n in 1...9 {
            bind(["\(n)", "<D-\(n)>"], "tab_switch \(n - 1)", "Switch to tab \(n)")
        }
        bind(["["], "tab_switch -1 --relative", "Previous tab")
        bind(["]"], "tab_switch 1 --relative", "Next tab")
        bind(["{"], "tab_swap -1", "Move tab left")
        bind(["}"], "tab_swap 1", "Move tab right")
        bind(["<C-c>"], "close", "Close tab")
        // Column dividers: ⌃←/⌃→ left one, ⌥←/⌥→ right one
        bind(["<C-Left>"], "resize_pane 0 -1", "Move left divider left")
        bind(["<C-Right>"], "resize_pane 0 1", "Move left divider right")
        bind(["<A-Left>"], "resize_pane 1 -1", "Move right divider left")
        bind(["<A-Right>"], "resize_pane 1 1", "Move right divider right")
        // App
        bind(["~", "<F1>"], "help", "Help")
        bind(["q"], "quit", "Quit")
        return b
    }()
}
