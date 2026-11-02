import Foundation

/// Everything a key can trigger. Parsed from yazi-style command strings (`arrow 1`, `cd ~/Downloads`)
/// so keymap.toml can use the same vocabulary.
public enum Action: Hashable, Sendable {
    public enum CopyTarget: String, Sendable { case path, dir, filename, nameWithoutExt = "name_without_ext" }

    case arrow(Int)
    /// Move by a fraction of the visible rows (0.5 = half page, -1 = page up).
    case arrowPage(Double)
    case top, bottom
    case leave, enter, open
    case back, forward
    case seekPreview(Int)
    case toggleSelect, selectAll, invertSelection, escape
    case toggleHidden
    case sort(SortBy, reverse: Bool)
    case toggleDirsFirst
    case linemode(Linemode)
    case cd(String)
    case copy(CopyTarget)
    /// Selected items (or the hovered one): to the Trash, or deleted immediately after confirmation.
    case remove(permanently: Bool)
    case visual(unset: Bool)
    case yank(cut: Bool), unyank, paste(overwrite: Bool), link
    case create, rename
    case openWith
    case cdPrompt
    case find(previous: Bool), findNext(previous: Bool), filter
    case search(content: Bool)
    case jump(fuzzy: Bool)
    case markSet(Character), markJump(Character), markList
    case tabNew, tabSwitch(Int), tabStep(Int), tabSwap(Int), tabClose
    case help, tasks, info
    /// Move column divider 0 (parent|current) or 1 (current|preview) by `steps` (one step = 24 pt).
    case resizePane(divider: Int, steps: Int)
    case viewer
    case quit

    public init?(command: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return nil }
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch verb {
        case "arrow":
            if arg == "top" { self = .top }
            else if arg == "bot" || arg == "bottom" { self = .bottom }
            else if arg.hasSuffix("%"), let v = Double(arg.dropLast()) { self = .arrowPage(v / 100) }
            else if let n = Int(arg) { self = .arrow(n) }
            else { return nil }
        case "leave": self = .leave
        case "enter": self = .enter
        case "open": self = .open
        case "back": self = .back
        case "forward": self = .forward
        case "seek": guard let n = Int(arg) else { return nil }; self = .seekPreview(n)
        case "toggle": self = .toggleSelect
        case "toggle_all": self = arg == "--state=on" ? .selectAll : .invertSelection
        case "escape": self = .escape
        case "hidden": self = .toggleHidden
        case "sort":
            let words = arg.split(separator: " ")
            guard let first = words.first, let by = SortBy(rawValue: String(first)) else { return nil }
            self = .sort(by, reverse: words.contains("--reverse"))
        case "dir_first": self = .toggleDirsFirst
        case "linemode": guard let m = Linemode(rawValue: arg) else { return nil }; self = .linemode(m)
        case "cd": guard !arg.isEmpty else { return nil }; self = .cd(arg)
        case "copy": guard let t = CopyTarget(rawValue: arg) else { return nil }; self = .copy(t)
        case "remove": self = .remove(permanently: arg == "--permanently")
        case "visual_mode": self = .visual(unset: arg == "--unset")
        case "yank": self = .yank(cut: arg == "--cut")
        case "unyank": self = .unyank
        case "paste": self = .paste(overwrite: arg == "--force")
        case "link": self = .link
        case "create": self = .create
        case "rename": self = .rename
        case "open_with": self = .openWith
        case "cd_interactive": self = .cdPrompt
        case "find": self = .find(previous: arg == "--previous")
        case "find_arrow": self = .findNext(previous: arg == "--previous")
        case "filter": self = .filter
        case "search": self = .search(content: arg == "rg" || arg == "content")
        case "jump": self = .jump(fuzzy: arg == "fzf")
        case "mark":
            if arg == "--list" { self = .markList; return }
            let words = arg.split(separator: " ")
            guard words.count == 2, words[1].count == 1, let c = words[1].first else { return nil }
            if words[0] == "set" { self = .markSet(c) } else if words[0] == "jump" { self = .markJump(c) } else { return nil }
        case "tab_create": self = .tabNew
        case "tab_switch":
            let words = arg.split(separator: " ")
            guard let n = words.first.flatMap({ Int($0) }) else { return nil }
            self = words.contains("--relative") ? .tabStep(n) : .tabSwitch(n)
        case "tab_swap": guard let n = Int(arg) else { return nil }; self = .tabSwap(n)
        case "close": self = .tabClose
        case "help": self = .help
        case "tasks_show": self = .tasks
        case "info": self = .info
        case "resize_pane":
            let w = arg.split(separator: " ").compactMap { Int($0) }
            guard w.count == 2, (0...1).contains(w[0]) else { return nil }
            self = .resizePane(divider: w[0], steps: w[1])
        case "view": self = .viewer
        case "quit": self = .quit
        default: return nil
        }
    }
}
