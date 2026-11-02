import AppKit
import FMCore

/// Visual mode, find, filter, go-to-path, recursive search, frecent jump and bookmarks (M5/M6).
extension BrowserViewController {
    // MARK: Visual mode (v / V)

    func toggleVisual(unset: Bool) {
        if visual != nil {
            visual = nil
            browserView.status.mode = "NOR"
            updateStatus()
            return
        }
        guard !current.entries.isEmpty else { return }
        visual = (current.cursor, unset, selection[cwd] ?? [])
        browserView.status.mode = unset ? "V-UNS" : "VIS"
        updateVisualSelection()
    }

    func updateVisualSelection() {
        guard let v = visual, !current.entries.isEmpty else { return }
        let lo = min(v.anchor, current.cursor), hi = max(v.anchor, current.cursor)
        let range = Set(current.entries[max(0, lo)...min(hi, current.entries.count - 1)].map(\.name))
        let s = v.unset ? v.base.subtracting(range) : v.base.union(range)
        selection[cwd] = s.isEmpty ? nil : s
        browserView.currentList.setSelected(s)
        updateStatus()
    }

    // MARK: Find (/ ? n N)

    func find(backward: Bool) {
        let start = current.cursor
        findBackward = backward
        browserView.prompt.begin(backward ? "Find previous:" : "Find:", onChange: { [weak self] q in
            guard let self else { return }
            findQuery = q.isEmpty ? nil : q
            if let i = nextMatch(q, from: start, backward: backward, inclusive: true) { moveCursor(to: i) }
            updateStatus()
        }, onCancel: { [weak self] in
            self?.findQuery = nil
            self?.moveCursor(to: start)
            self?.updateStatus()
        }) { [weak self] q in
            self?.findQuery = q.isEmpty ? nil : q
            self?.updateStatus()
        }
    }

    func findNext(previous: Bool) {
        guard let q = findQuery else { return }
        let backward = findBackward != previous
        if let i = nextMatch(q, from: current.cursor, backward: backward, inclusive: false) {
            moveCursor(to: i)
        } else {
            NSSound.beep()
        }
    }

    /// Smart case: an uppercase letter in the query makes it case-sensitive. Wraps around.
    func nextMatch(_ query: String, from start: Int, backward: Bool, inclusive: Bool) -> Int? {
        let n = current.entries.count
        guard n > 0, !query.isEmpty else { return nil }
        let sensitive = query.contains { $0.isUppercase }
        for step in (inclusive ? 0 : 1)...(inclusive ? n - 1 : n) {
            let i = ((backward ? start - step : start + step) % n + n) % n
            let name = current.entries[i].name
            if sensitive ? name.contains(query) : name.localizedCaseInsensitiveContains(query) { return i }
        }
        return nil
    }

    // MARK: Filter (f)

    func filterPrompt() {
        let dir = cwd
        let previous = filters[dir]
        browserView.prompt.begin("Filter:", text: previous ?? "", onChange: { [weak self] q in
            guard let self, cwd == dir else { return }
            setFilter(q.isEmpty ? nil : q)
        }, onCancel: { [weak self] in
            guard let self, cwd == dir else { return }
            setFilter(previous)
        }) { [weak self] q in
            guard let self, cwd == dir else { return }
            setFilter(q.isEmpty ? nil : q)
        }
    }

    func setFilter(_ q: String?) {
        guard filters[cwd] != q else { return }
        filters[cwd] = q
        current = refreshed(current)
        render(browserView.currentList, current)
        updatePreview()
    }

    // MARK: Go to path (g␣, ⌘L, ⌘⇧G)

    func cdPrompt() {
        let start = abbreviate(cwd) + (cwd == "/" ? "" : "/")
        browserView.prompt.begin("Go to:", text: start, select: NSRange(location: (start as NSString).length, length: 0),
                                 onComplete: { [weak self] text in self?.completePath(text) }) { [weak self] text in
            guard let self, !text.isEmpty else { return }
            let path = normalize(text)
            if isDirectory(path) {
                cd(path)
            } else if FileOps.exists(path) {
                reveal(path)
            } else {
                NSSound.beep()
                showFlash("No such folder: \(text)")
            }
        }
    }

    /// Tab completion: longest common prefix of the folders matching the last component.
    func completePath(_ text: String) -> String? {
        let expanded = (text as NSString).expandingTildeInPath
        let base = expanded.hasPrefix("/") ? expanded : join(cwd, expanded)
        let dir = base.hasSuffix("/") ? String(base.dropLast()) : (base as NSString).deletingLastPathComponent
        let partial = base.hasSuffix("/") ? "" : (base as NSString).lastPathComponent
        guard let entries = try? DirLister.list(dir.isEmpty ? "/" : dir) else { return nil }
        let names = entries.filter { $0.isDirectoryLike && $0.name.lowercased().hasPrefix(partial.lowercased())
            && ($0.name.hasPrefix(".") == partial.hasPrefix(".")) }.map(\.name).sorted()
        guard var common = names.first else { NSSound.beep(); return nil }
        for n in names.dropFirst() {
            while !n.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        let prefix = String(text.dropLast(partial.count))
        return prefix + (names.count == 1 ? names[0] + "/" : common)
    }

    /// cd to the item's folder with the cursor on it.
    func reveal(_ path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        cd(parent.isEmpty ? "/" : parent, focus: (path as NSString).lastPathComponent)
    }

    // MARK: Recursive search (s, ⌘F, Z) and content search (S)

    /// `fuzzy` (Z) matches the whole relative path; plain (s) matches file names.
    func searchNames(fuzzy: Bool) {
        let root = cwd, showHidden = options.showHidden
        let picker = browserView.picker
        searchTask?.cancel()
        picker.present(fuzzy ? "Find in \(abbreviate(root))" : "Search names in \(abbreviate(root))",
                       placeholder: fuzzy ? "Fuzzy path" : "File name", items: [],
                       onClose: { [weak self] in self?.searchTask?.cancel() }) { [weak self] item in
            guard let self else { return }
            reveal(join(root, item.payload))
        }
        picker.isLoading = true
        searchTask = Task {
            let stream = AsyncStream<[Walker.Hit]> { cont in
                let walk = Task.detached(priority: .userInitiated) {
                    Walker.walk(root, showHidden: showHidden) { cont.yield($0) }
                    cont.finish()
                }
                cont.onTermination = { _ in walk.cancel() }
            }
            for await batch in stream {
                guard !Task.isCancelled, picker.isActive else { return }
                picker.appendItems(batch.map { hit in
                    let name = (hit.path as NSString).lastPathComponent
                    let parent = (hit.path as NSString).deletingLastPathComponent
                    return PickerItem(title: name, detail: parent.isEmpty ? "." : parent,
                                      symbol: hit.isDirectory ? "folder" : "doc", payload: hit.path,
                                      matchText: fuzzy ? hit.path : name)
                })
            }
            picker.isLoading = false
        }
    }

    func searchContents() {
        let root = cwd, showHidden = options.showHidden
        let picker = browserView.picker
        searchTask?.cancel()
        picker.present("Search contents in \(abbreviate(root))", placeholder: "Text or regex (ripgrep, smart case)",
                       items: [], onQuery: { [weak self] q in self?.runContentSearch(q, root: root, showHidden: showHidden) },
                       onClose: { [weak self] in self?.searchTask?.cancel() }) { [weak self] item in
            guard let self else { return }
            reveal(join(root, item.payload))
        }
    }

    func runContentSearch(_ query: String, root: String, showHidden: Bool) {
        searchTask?.cancel()
        let picker = browserView.picker
        picker.setItems([])
        guard !query.isEmpty else { picker.isLoading = false; return }
        picker.isLoading = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200)) // debounce typing
            if Task.isCancelled { return }
            let stream = AsyncStream<[PickerItem]> { cont in
                let run = Task.detached(priority: .userInitiated) {
                    ContentSearch.run(query, in: root, hidden: showHidden) { cont.yield($0) }
                    cont.finish()
                }
                cont.onTermination = { _ in run.cancel() }
            }
            for await batch in stream {
                if Task.isCancelled || !picker.isActive { return }
                picker.appendItems(batch)
            }
            if !Task.isCancelled { picker.isLoading = false }
        }
    }

    // MARK: Frecent jump (z)

    func jumpRecent() {
        let fm = FileManager.default
        let items = Prefs.frecentFolders().prefix(500).filter { $0 != cwd && fm.fileExists(atPath: $0) }.map { p in
            PickerItem(title: (p as NSString).lastPathComponent.isEmpty ? "/" : (p as NSString).lastPathComponent,
                       detail: abbreviate(p), symbol: "clock.arrow.circlepath", payload: p, matchText: abbreviate(p))
        }
        browserView.picker.present("Jump to a recent folder", items: items) { [weak self] item in
            self?.cd(item.payload)
        }
    }

    // MARK: Bookmarks (b<char>, '<char>, '')

    func setBookmark(_ c: Character) {
        var marks = Prefs.bookmarks
        marks[String(c)] = cwd
        Prefs.bookmarks = marks
        showFlash("Bookmark ‘\(c)’ → \(abbreviate(cwd))")
    }

    func jumpBookmark(_ c: Character) {
        guard let path = Prefs.bookmarks[String(c)] else {
            NSSound.beep()
            showFlash("No bookmark ‘\(c)’ (set one with b\(c))")
            return
        }
        cd(path)
    }

    func listBookmarks() {
        let items = Prefs.bookmarks.sorted { $0.key < $1.key }.map { key, path in
            PickerItem(title: "\(key)   \((path as NSString).lastPathComponent)", detail: abbreviate(path),
                       symbol: "bookmark", payload: path, matchText: key + " " + path)
        }
        browserView.picker.present("Bookmarks", placeholder: items.isEmpty ? "No bookmarks yet: press b then a letter to add one"
                                   : "Type to filter", items: items) { [weak self] item in
            self?.cd(item.payload)
        }
    }
}

/// ripgrep (or grep) runner for `S`. Results are relative to `root`.
enum ContentSearch {
    static let rg: String? = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"].first {
        FileManager.default.isExecutableFile(atPath: $0)
    }

    static func run(_ query: String, in root: String, hidden: Bool, limit: Int = 2000, onBatch: ([PickerItem]) -> Void) {
        let p = Process()
        if let rg {
            p.executableURL = URL(fileURLWithPath: rg)
            p.arguments = ["--line-number", "--no-heading", "--color=never", "--smart-case", "--max-count=20",
                           "--max-columns=300", "--max-columns-preview"] + (hidden ? ["--hidden"] : []) + ["--", query, "."]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            p.arguments = ["-rnI", "--max-count=20", "-e", query, "."]
        }
        p.currentDirectoryURL = URL(fileURLWithPath: root)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        let handle = out.fileHandleForReading
        var buffer = Data()
        var batch: [PickerItem] = []
        var count = 0
        while !Task.isCancelled, count < limit {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let item = parse(line) { batch.append(item); count += 1 }
            }
            if !batch.isEmpty { onBatch(batch); batch.removeAll() }
        }
        if p.isRunning { p.terminate() }
    }

    /// `./path/file.swift:12:text` → item.
    static func parse(_ line: String) -> PickerItem? {
        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let n = Int(parts[1]) else { return nil }
        var path = String(parts[0])
        if path.hasPrefix("./") { path.removeFirst(2) }
        let text = parts[2].trimmingCharacters(in: .whitespaces)
        return PickerItem(title: text.isEmpty ? " " : text, detail: "\(path):\(n)", symbol: "text.magnifyingglass",
                          payload: path, matchText: text)
    }
}
