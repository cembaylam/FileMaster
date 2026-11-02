import AppKit
import FMCore

/// which-key, help (~ / F1), tasks (w), info (⌘I).
extension BrowserViewController {
    // MARK: which-key

    func scheduleWhichKey() {
        whichKeyTask?.cancel()
        whichKeyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, keys.isPending else { return }
            browserView.showWhichKey(whichKeyEntries())
        }
    }

    func hideWhichKey() {
        whichKeyTask?.cancel()
        if !browserView.whichKey.isHidden { browserView.showWhichKey([]) }
    }

    /// Bookmark prefixes would list 62 single characters; show the useful summary instead.
    func whichKeyEntries() -> [(key: String, desc: String)] {
        let marks = Prefs.bookmarks.sorted { $0.key < $1.key }
        switch pendingKeys {
        case "b":
            return [("a–Z 0–9", "Bookmark this folder")] + marks.map { ($0.key, "replace → " + abbreviate($0.value)) }
        case "'":
            return [("'", "List bookmarks")] + marks.map { ($0.key, abbreviate($0.value)) }
        default:
            // a b c … then A B C …, like yazi's which-key.
            func rank(_ k: String) -> (String, Int) { (k.lowercased(), k.first?.isUppercase == true ? 1 : 0) }
            return keys.choices.sorted { rank($0.key) < rank($1.key) }
        }
    }

    // MARK: Help

    func showHelp() {
        // One row per command, with all its keys; bookmark rows collapsed.
        var rows: [(desc: String, keys: [String], action: Action?)] = []
        var index: [String: Int] = [:]
        for b in keymap.bindings {
            let seq = b.keys.joined(separator: " ")
            if b.keys.count == 2, ["b", "'"].contains(b.keys[0]), b.keys[1] != "'" {
                let desc = b.keys[0] == "b" ? "Set bookmark" : "Jump to bookmark"
                if index[desc] == nil { index[desc] = rows.count; rows.append((desc, [b.keys[0] + "<char>"], nil)) }
                continue
            }
            if let i = index[b.desc] {
                if !rows[i].keys.contains(seq) { rows[i].keys.append(seq) }
            } else {
                index[b.desc] = rows.count
                rows.append((b.desc, [seq], b.action))
            }
        }
        let items = rows.enumerated().map { i, r in
            let keys = r.keys.map { $0.split(separator: " ").map { WhichKeyView.display(String($0)) }.joined() }
                .joined(separator: "  ")
            return PickerItem(title: r.desc, detail: keys, symbol: "keyboard", payload: String(i), matchText: r.desc + " " + keys)
        }
        browserView.picker.present("Keyboard shortcuts — Return runs the command", placeholder: "Search commands", items: items) {
            [weak self] item in
            guard let self, let i = Int(item.payload), let action = rows[i].action else { return }
            perform(action)
        }
    }

    // MARK: Tasks (w)

    func showTasks() {
        let items = TaskCenter.shared.items.reversed().map { t -> PickerItem in
            let (detail, symbol): (String, String) = switch t.state {
            case let .running(done, total): ("\(done)/\(total)", "arrow.triangle.2.circlepath")
            case .finished: ("done · " + Format.date(t.started.timeIntervalSince1970), "checkmark.circle")
            case let .failed(msg): ("failed: " + msg, "exclamationmark.triangle")
            }
            return PickerItem(title: t.title, detail: detail, symbol: symbol, payload: String(t.id))
        }
        browserView.picker.present("Tasks", placeholder: items.isEmpty ? "No tasks yet" : "Type to filter", items: Array(items)) { _ in }
    }

    // MARK: Info (⌘I)

    func showInfo() {
        guard let e = current.hovered else { return }
        let path = join(cwd, e.name)
        let kind = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.localizedTypeDescriptionKey]))?
            .localizedTypeDescription ?? (e.isDirectoryLike ? "Folder" : "File")
        var rows: [(String, String, String)] = [
            ("Name", e.name, "name"),
            ("Kind", kind, "kind"),
            ("Size", e.isDirectoryLike ? "Calculating…" : "\(Format.size(e.size)) (\(e.size.formatted()) bytes)", "size"),
            ("Where", abbreviate(cwd), "where"),
            ("Created", Format.date(e.created), "created"),
            ("Modified", Format.date(e.modified), "modified"),
            ("Permissions", Format.permissions(e) + String(format: "  (%o)", e.mode), "perm"),
            ("Owner", Format.user(e.uid), "owner"),
        ]
        if e.kind == .symlink, let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            rows.append(("Link to", target, "link"))
        }
        if let mark = gitSnapshot?.marks(in: cwd), let m = mark.all ?? mark.byName[e.name] {
            rows.append(("Git", String(describing: m), "git"))
        }
        let items = rows.map { PickerItem(title: $0.0, detail: $0.1, payload: $0.2, matchText: $0.0 + " " + $0.1) }
        let picker = browserView.picker
        infoTask?.cancel()
        picker.present("Info — Return copies the value", items: items, onClose: { [weak self] in self?.infoTask?.cancel() }) { item in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.payload == "where" ? path : item.detail, forType: .string)
        }
        if e.isDirectoryLike {
            infoTask = Task {
                let total = await Task.detached(priority: .userInitiated) { Walker.totalSize(path) }.value
                guard !Task.isCancelled, picker.isActive else { return }
                picker.updateItem(payload: "size", detail: "\(Format.size(total.bytes)) · \(total.files.formatted()) files")
            }
        }
    }
}
