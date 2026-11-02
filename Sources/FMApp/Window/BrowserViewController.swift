import AppKit
import FMCore
import FMPreview

/// One directory column's state.
struct DirState {
    let path: String
    var entries: [FileEntry] = []
    var cursor = 0
    var loaded = false
    var error: String?
    /// Name to put the cursor on once the listing arrives.
    var pendingFocus: String?

    var hovered: FileEntry? { entries.indices.contains(cursor) ? entries[cursor] : nil }
}

/// Owns one browser tab's state and drives the three columns. Tabs are native window tabs, one controller each.
/// Feature groups live in extensions: +Ops (file operations), +Find (find/filter/search/jump/bookmarks),
/// +Overlays (help, info, tasks, which-key).
@MainActor
final class BrowserViewController: NSViewController {
    let dirs = DirectoryService.shared
    let keymap = KeymapConfig.load()
    lazy var keys = KeyEngine(bindings: keymap.bindings)
    var options = Prefs.viewOptions
    var linemode: Linemode = Prefs.linemode

    private(set) var cwd = ""
    var current = DirState(path: "")
    var parentDir: DirState?
    var previewDir: DirState?
    var cursorMemory: [String: String] = [:]
    var selection: [String: Set<String>] = [:]
    var backStack: [String] = []
    var forwardStack: [String] = []
    var pendingKeys = ""
    var whichKeyTask: Task<Void, Never>?

    /// Visual mode (`v`/`V`): anchor row, unset mode, and the selection when it started.
    var visual: (anchor: Int, unset: Bool, base: Set<String>)?
    /// Live filter per directory (`f`).
    var filters: [String: String] = [:]
    /// Last find query (`/` `?`, repeated by `n` `N`).
    var findQuery: String?
    var findBackward = false
    /// Transient message in the status bar until the next cursor move.
    var flash: String?

    var gitSnapshot: GitStatus.Snapshot?
    var gitTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var infoTask: Task<Void, Never>?

    /// Tab actions are handled by the window controller (native window tabs).
    var onTabAction: ((Action) -> Void)?

    var previewTask: Task<Void, Never>?
    var previewGeneration = 0
    var previewCache: [String: PreviewResult] = [:]
    var previewCacheOrder: [String] = []

    let initialPath: String
    var onPathChange: ((String) -> Void)?
    var onShowHiddenChange: ((Bool) -> Void)?
    var showsHidden: Bool { options.showHidden }

    lazy var watcher = FSWatcher { [weak self] paths in
        Task { @MainActor in self?.filesystemChanged(paths) }
    }

    var browserView: BrowserView { view as! BrowserView }

    init(path: String) {
        initialPath = path
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = BrowserView(frame: NSRect(x: 0, y: 0, width: 1200, height: 720))
        v.controller = self
        view = v
    }

    func start() {
        let v = browserView
        v.currentList.onClick = { [weak self] i in self?.moveCursor(to: i) }
        v.currentList.onDoubleClick = { [weak self] i in self?.moveCursor(to: i); self?.perform(.open) }
        v.currentList.onScrollRows = { [weak self] rows in
            guard let self else { return }
            moveCursor(to: current.cursor + rows)
        }
        v.parentList.onClick = { [weak self] i in
            guard let self, let p = parentDir, p.entries.indices.contains(i) else { return }
            let e = p.entries[i]
            if e.isDirectoryLike { cd(join(p.path, e.name)) } else { cd(p.path, focus: e.name) }
        }
        v.preview.dirList.onClick = { [weak self] i in
            guard let self, let d = previewDir, d.entries.indices.contains(i) else { return }
            cd(d.path, focus: d.entries[i].name)
        }
        v.preview.dirList.onDoubleClick = { [weak self] i in
            guard let self, let d = previewDir, d.entries.indices.contains(i) else { return }
            cd(d.path, focus: d.entries[i].name)
            perform(.open)
        }
        for list in [v.parentList, v.currentList, v.preview.dirList] { list.linemode = linemode }
        v.parentList.linemode = .none
        cd(initialPath, history: false)
        if !keymap.errors.isEmpty { showFlash("keymap.toml: " + keymap.errors.joined(separator: "; ")) }
        NotificationCenter.default.addObserver(self, selector: #selector(prefsDidChange), name: Prefs.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tasksDidChange), name: TaskCenter.didChange, object: nil)
    }

    @objc func prefsDidChange() {
        let o = Prefs.viewOptions
        if o != options {
            options = o
            reapplyOptions()
            onShowHiddenChange?(options.showHidden)
        }
        if Prefs.linemode != linemode { perform(.linemode(Prefs.linemode)) }
        refreshGit()
    }

    @objc func tasksDidChange() { updateStatus() }

    func showFlash(_ message: String) {
        flash = message
        updateStatus()
    }

    // MARK: Keys

    func claimsKey(_ token: String) -> Bool { keys.accepts(token) }

    func handleKey(_ token: String) -> Bool {
        if browserView.isViewerOpen { return handleViewerKey(token) }
        let outcome = keys.feed(token)
        if case .pending = outcome {} else { hideWhichKey() }
        switch outcome {
        case let .action(a):
            pendingKeys = ""
            perform(a)
            return true
        case let .pending(seq):
            pendingKeys = seq
            updateStatus()
            scheduleWhichKey()
            return true
        case .cancelled:
            pendingKeys = ""
            updateStatus()
            return true
        case .unbound:
            return false
        }
    }

    func perform(_ action: Action) {
        switch action {
        case let .arrow(n): moveCursor(to: current.cursor + n)
        case let .arrowPage(f):
            let rows = Int((Double(browserView.currentList.visibleRows) * f).rounded())
            moveCursor(to: current.cursor + (rows == 0 ? (f < 0 ? -1 : 1) : rows))
        case .top: moveCursor(to: 0)
        case .bottom: moveCursor(to: current.entries.count - 1)
        case .leave:
            if let p = parentPath(cwd) { cd(p, focus: lastComponent(cwd)) }
        case .enter:
            // Only folders: files open with Enter/o (default app) or Space (built-in viewer).
            guard let e = current.hovered, e.isDirectoryLike else { return }
            cd(join(cwd, e.name))
        case .open:
            guard let e = current.hovered else { return }
            if e.isDirectoryLike && e.extensionLowercased != "app" { cd(join(cwd, e.name)) } else { open(e) }
        case .back:
            guard let p = backStack.popLast() else { return }
            forwardStack.append(cwd)
            cd(p, history: false)
        case .forward:
            guard let p = forwardStack.popLast() else { return }
            backStack.append(cwd)
            cd(p, history: false)
        case let .seekPreview(n): browserView.preview.seek(lines: n)
        case .toggleSelect:
            guard let e = current.hovered else { return }
            var s = selection[cwd, default: []]
            if s.remove(e.name) == nil { s.insert(e.name) }
            selection[cwd] = s.isEmpty ? nil : s
            browserView.currentList.setSelected(s)
            moveCursor(to: current.cursor + 1)
            updateStatus()
        case .selectAll:
            selection[cwd] = Set(current.entries.map(\.name))
            browserView.currentList.setSelected(selection[cwd] ?? [])
            updateStatus()
        case .invertSelection:
            let s = Set(current.entries.map(\.name)).subtracting(selection[cwd] ?? [])
            selection[cwd] = s.isEmpty ? nil : s
            browserView.currentList.setSelected(s)
            updateStatus()
        case .escape:
            // yazi order: visual mode → selection → filter → find.
            if visual != nil {
                visual = nil
                browserView.status.mode = "NOR"
            } else if selection[cwd] != nil || !selection.isEmpty {
                selection.removeAll()
                browserView.currentList.setSelected([])
            } else if filters[cwd] != nil {
                setFilter(nil)
            } else {
                findQuery = nil
            }
            updateStatus()
        case .toggleHidden:
            options.showHidden.toggle()
            Prefs.viewOptions = options
            reapplyOptions()
            onShowHiddenChange?(options.showHidden)
        case let .sort(by, reverse):
            options.sort.by = by
            options.sort.reverse = reverse
            Prefs.viewOptions = options
            reapplyOptions()
        case .toggleDirsFirst:
            options.sort.dirsFirst.toggle()
            Prefs.viewOptions = options
            reapplyOptions()
        case let .linemode(m):
            linemode = m
            Prefs.linemode = m
            browserView.currentList.linemode = m
            browserView.preview.dirList.linemode = m
        case let .cd(path): cd(path)
        case let .copy(target): copy(target)
        case let .remove(permanently): remove(permanently: permanently)
        case let .visual(unset): toggleVisual(unset: unset)
        case let .yank(cut): yank(cut: cut)
        case .unyank: unyank()
        case let .paste(overwrite): paste(overwrite: overwrite)
        case .link: link()
        case .create: create()
        case .rename: rename()
        case .openWith: openWith()
        case .cdPrompt: cdPrompt()
        case let .find(previous): find(backward: previous)
        case let .findNext(previous): findNext(previous: previous)
        case .filter: filterPrompt()
        case let .search(content): content ? searchContents() : searchNames(fuzzy: false)
        case let .jump(fuzzy): fuzzy ? searchNames(fuzzy: true) : jumpRecent()
        case let .markSet(c): setBookmark(c)
        case let .markJump(c): jumpBookmark(c)
        case .markList: listBookmarks()
        case .tabNew, .tabSwitch, .tabStep, .tabSwap, .tabClose: onTabAction?(action)
        case let .resizePane(divider, steps): browserView.moveDivider(divider, by: CGFloat(steps) * 24)
        case .help: showHelp()
        case .tasks: showTasks()
        case .info: showInfo()
        case .viewer: openViewer()
        case .quit: NSApp.terminate(nil)
        }
    }

    // MARK: Viewer (Space)

    func openViewer() {
        guard let e = current.hovered, !e.isDirectoryLike else { return }
        let v = browserView
        if !v.isViewerOpen {
            v.setViewerOpen(true)
            v.status.mode = "VIEW"
            updateChrome()
        }
        v.viewer.show(path: join(cwd, e.name), size: e.size)
    }

    var isFullScreen: Bool { view.window?.styleMask.contains(.fullScreen) ?? false }
    /// Instant full screen for the viewer (`f`); see FastFullScreen.
    var fastFullScreen: FastFullScreen?

    func toggleFastFullScreen() {
        if let fs = fastFullScreen {
            fastFullScreen = nil
            fs.exit()
        } else if isFullScreen {
            view.window?.toggleFullScreen(nil) // native full screen entered via the green button
        } else {
            fastFullScreen = FastFullScreen(viewer: browserView.viewer, home: browserView)
        }
    }

    func closeViewer() {
        if fastFullScreen != nil { toggleFastFullScreen() }
        browserView.viewer.close()
        browserView.setViewerOpen(false)
        browserView.status.mode = "NOR"
        updateChrome()
    }

    /// Full-screen viewer shows only the content: toolbar and status bar hidden. `fullScreen` is passed by the
    /// window's will-enter/will-exit callbacks, before `styleMask` reflects the new state.
    func updateChrome(fullScreen: Bool? = nil) {
        let immersive = (fullScreen ?? isFullScreen) && browserView.isViewerOpen
        view.window?.toolbar?.isVisible = !immersive
        browserView.isImmersive = immersive
    }

    /// Next/previous non-directory entry, shown in the viewer.
    func stepViewer(_ direction: Int) {
        var i = current.cursor + direction
        while current.entries.indices.contains(i) {
            if !current.entries[i].isDirectoryLike {
                moveCursor(to: i)
                openViewer()
                return
            }
            i += direction
        }
    }

    /// Viewer keymap (docs/MEDIA.md §3). Media keys first; the rest apply to every viewer type.
    func handleViewerKey(_ token: String) -> Bool {
        let viewer = browserView.viewer
        if viewer.hasMedia {
            switch token {
            case "<Space>": viewer.togglePlay(); return true
            case "<Left>": viewer.seek(by: -10); return true
            case "<Right>": viewer.seek(by: 10); return true
            case "<S-Left>", "H": viewer.seek(by: -30); return true
            case "<S-Right>", "L": viewer.seek(by: 30); return true
            case "<Up>": viewer.changeVolume(0.05); return true
            case "<Down>": viewer.changeVolume(-0.05); return true
            case "m": viewer.toggleMute(); return true
            case ",": viewer.stepFrame(-1); return true
            case ".": viewer.stepFrame(1); return true
            case "[": viewer.changeRate(-0.25); return true
            case "]": viewer.changeRate(0.25); return true
            case "=": viewer.resetRate(); return true
            case let t where t.count == 1 && t.first!.isASCII && t.first!.isNumber:
                viewer.seek(toFraction: Double(t)! / 10)
                return true
            default: break
            }
        }
        if viewer.isScrollable {
            switch token {
            case "<Up>": viewer.scroll(points: -40); return true
            case "<Down>": viewer.scroll(points: 40); return true
            case "<PageUp>": viewer.scroll(pages: -1); return true
            case "<PageDown>": viewer.scroll(pages: 1); return true
            default: break
            }
        }
        switch token {
        case "<Esc>":
            // First Esc leaves fullscreen, the next one closes the viewer.
            if fastFullScreen != nil || isFullScreen { toggleFastFullScreen() } else { closeViewer() }
        case "q", "<Space>": closeViewer()
        case "j", "n", "<Down>", "<Right>": stepViewer(1)
        case "k", "p", "<Up>", "<Left>": stepViewer(-1)
        case "J": viewer.seek(lines: 5)
        case "K": viewer.seek(lines: -5)
        case "f", "F":
            toggleFastFullScreen()
        case "o", "<Enter>": perform(.open)
        default: return false
        }
        return true
    }

    // MARK: Navigation

    func cd(_ rawPath: String, focus: String? = nil, history: Bool = true) {
        let path = normalize(rawPath)
        guard isDirectory(path) else {
            NSSound.beep()
            return
        }
        if let name = current.hovered?.name { cursorMemory[cwd] = name }
        if history && !cwd.isEmpty && path != cwd {
            backStack.append(cwd)
            forwardStack.removeAll()
        }
        if path != cwd {
            if visual != nil { visual = nil; browserView.status.mode = "NOR" }
            Prefs.lastFolder = path
            Prefs.recordVisit(path)
        }
        flash = nil
        cwd = path
        current = makeState(path, focus: focus ?? cursorMemory[path])
        parentDir = parentPath(path).map { makeState($0, focus: lastComponent(path)) }
        watcher.watch(parentDir.map { [$0.path, path] } ?? [path])
        onPathChange?(path)

        render(browserView.parentList, parentDir)
        render(browserView.currentList, current)
        updatePreview()
        refreshGit()
    }

    func moveCursor(to index: Int) {
        guard !current.entries.isEmpty else { return }
        let i = min(max(0, index), current.entries.count - 1)
        guard i != current.cursor else { return }
        current.cursor = i
        flash = nil
        browserView.currentList.moveCursor(to: i)
        if visual != nil { updateVisualSelection() }
        updatePreview()
    }

    /// Cache hit → synchronous (no flicker); miss → empty column now, listing when it arrives.
    func makeState(_ path: String, focus: String?) -> DirState {
        var s = DirState(path: path)
        if let cached = dirs.cachedView(path, options) {
            let v = filtered(path, cached)
            s.entries = v
            s.loaded = true
            s.cursor = focus.flatMap { n in v.firstIndex { $0.name == n } } ?? 0
        } else {
            s.pendingFocus = focus
            load(path)
        }
        return s
    }

    func load(_ path: String, force: Bool = false) {
        let options = self.options
        Task { [weak self, dirs] in
            let result: Result<[FileEntry], Error>
            do { result = .success(try await dirs.load(path, options, force: force)) } catch { result = .failure(error) }
            self?.apply(path, result, options: options)
        }
    }

    func apply(_ path: String, _ result: Result<[FileEntry], Error>, options: ViewOptions) {
        guard options == self.options else { return } // a newer load with current options is in flight
        if current.path == path {
            let before = current.hovered
            merge(&current, result)
            render(browserView.currentList, current)
            if before != current.hovered || previewDir == nil && current.hovered?.isDirectoryLike == true {
                updatePreview()
            } else {
                updateStatus()
            }
        }
        if parentDir?.path == path {
            merge(&parentDir!, result)
            render(browserView.parentList, parentDir)
        }
        if previewDir?.path == path {
            merge(&previewDir!, result)
            render(browserView.preview.dirList, previewDir)
        }
    }

    func merge(_ s: inout DirState, _ result: Result<[FileEntry], Error>) {
        let focus = s.pendingFocus ?? (s.loaded ? s.hovered?.name : nil)
        switch result {
        case let .success(v):
            s.entries = filtered(s.path, v)
            s.error = nil
        case let .failure(e):
            s.entries = []
            s.error = (e as? DirLister.Failure)?.description ?? e.localizedDescription
        }
        s.loaded = true
        s.pendingFocus = nil
        if let focus, let i = s.entries.firstIndex(where: { $0.name == focus }) {
            s.cursor = i
        } else {
            s.cursor = min(s.cursor, max(0, s.entries.count - 1))
        }
    }

    func render(_ list: FileListView, _ s: DirState?) {
        guard let s else {
            list.update(entries: [], cursor: 0, selected: [], message: nil)
            return
        }
        list.dirPath = s.path
        let message = s.error ?? (s.loaded && s.entries.isEmpty ? (filters[s.path] != nil ? "No matches" : "Empty") : nil)
        list.update(entries: s.entries, cursor: s.cursor, selected: selection[s.path] ?? [], message: message)
        let git = gitSnapshot.map { $0.marks(in: s.path) }
        list.setGit(git?.byName ?? [:], all: git?.all)
    }

    /// Applies the live filter (`f`) for `path`, if any. Case-insensitive substring, like yazi's default.
    func filtered(_ path: String, _ entries: [FileEntry]) -> [FileEntry] {
        guard let q = filters[path], !q.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Git (M6)

    /// Re-runs `git status` for the repo containing cwd (off the main thread) and re-renders the columns.
    func refreshGit() {
        gitTask?.cancel()
        guard Prefs.showGitStatus else {
            if gitSnapshot != nil { gitSnapshot = nil; renderAll() }
            return
        }
        let dir = cwd
        gitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return }
            let snap = await Task.detached(priority: .utility) { () -> GitStatus.Snapshot? in
                guard let root = GitStatus.repoRoot(for: dir) else { return nil }
                return GitStatus.snapshot(root: root)
            }.value
            guard let self, !Task.isCancelled, dir == self.cwd else { return }
            if snap == nil && self.gitSnapshot == nil { return }
            self.gitSnapshot = snap
            self.renderAll()
        }
    }

    func renderAll() {
        render(browserView.parentList, parentDir)
        render(browserView.currentList, current)
        if let previewDir { render(browserView.preview.dirList, previewDir) }
    }

    func reapplyOptions() {
        current = refreshed(current)
        parentDir = parentDir.map(refreshed)
        render(browserView.parentList, parentDir)
        render(browserView.currentList, current)
        updatePreview()
    }

    /// Re-derive a column under new options, keeping its cursor on the same name.
    func refreshed(_ s: DirState) -> DirState {
        var n = makeState(s.path, focus: s.hovered?.name ?? s.pendingFocus)
        if !n.loaded {
            n.entries = s.entries // keep showing old order until the re-sort lands
            n.cursor = s.cursor
        }
        return n
    }

    /// FSEvents reports resolved paths (`/private/tmp/…` for `/tmp/…`), so compare on real paths too.
    func filesystemChanged(_ paths: Set<String>) {
        func changed(_ p: String) -> Bool { paths.contains(p) || paths.contains(realPath(p)) }
        for path in [current.path, parentDir?.path, previewDir?.path].compactMap({ $0 }) where changed(path) {
            load(path, force: true)
        }
        if let e = current.hovered, !e.isDirectoryLike, changed(join(cwd, e.name)) {
            previewCache.removeValue(forKey: previewKey(e))
        }
        if gitSnapshot != nil || paths.contains(where: { $0.hasSuffix("/.git") || $0.contains("/.git/") }) {
            refreshGit()
        }
    }

    var realPathCache: [String: String] = [:]

    func realPath(_ p: String) -> String {
        if let r = realPathCache[p] { return r }
        let r = p.withCString { c -> String in
            guard let out = realpath(c, nil) else { return p }
            defer { free(out) }
            return String(cString: out)
        }
        if realPathCache.count > 256 { realPathCache.removeAll() }
        realPathCache[p] = r
        return r
    }

    // MARK: Preview

    func updatePreview() {
        previewTask?.cancel()
        previewGeneration &+= 1
        updateStatus()
        let pane = browserView.preview

        guard let e = current.hovered else {
            previewDir = nil
            pane.showNothing()
            return
        }
        let path = join(cwd, e.name)

        if e.isDirectoryLike {
            let remembered = cursorMemory[path]
            previewDir = makeState(path, focus: remembered)
            pane.dirList.showsCursor = remembered != nil
            render(pane.dirList, previewDir)
            pane.showDirectory()
            return
        }
        previewDir = nil

        let key = previewKey(e)
        if let cached = previewCache[key] {
            pane.show(cached)
            return
        }
        pane.showNothing()
        let generation = previewGeneration
        let maxPixel = pane.maxPixel
        let scale = view.window?.backingScaleFactor ?? 2
        previewTask = Task { [weak self] in
            // Let key-repeat bursts cancel us before doing any I/O.
            try? await Task.sleep(for: .milliseconds(12))
            if Task.isCancelled { return }
            let result = await QuickPreview.load(path: path, size: e.size, maxPixel: maxPixel, scale: scale)
            guard let self, !Task.isCancelled, generation == self.previewGeneration else { return }
            self.cachePreview(key, result)
            self.browserView.preview.show(result)
        }
    }

    func previewKey(_ e: FileEntry) -> String { "\(join(cwd, e.name))|\(e.modified)|\(e.size)" }

    func cachePreview(_ key: String, _ result: PreviewResult) {
        previewCache[key] = result
        previewCacheOrder.append(key)
        if previewCacheOrder.count > 48 { previewCache.removeValue(forKey: previewCacheOrder.removeFirst()) }
    }

    // MARK: Status

    func updateStatus() {
        let status = browserView.status
        if let flash {
            status.left = flash
        } else if let e = current.hovered {
            var parts = [Format.permissions(e)]
            if !e.isDirectoryLike { parts.append(Format.size(e.size)) }
            parts.append(Format.date(e.modified))
            parts.append(Format.user(e.uid))
            status.left = parts.joined(separator: "   ")
        } else {
            status.left = current.error ?? ""
        }
        var right: [String] = []
        if !pendingKeys.isEmpty { right.append(pendingKeys) }
        let running = TaskCenter.shared.running
        if running > 0 { right.append("⟳ \(running) task\(running == 1 ? "" : "s")") }
        if let y = Self.yanked { right.append("\(y.paths.count) \(y.cut ? "cut" : "yanked")") }
        if let f = filters[cwd] { right.append("filter: \(f)") }
        if let q = findQuery { right.append("find: \(q)") }
        let selected = selection.values.reduce(0) { $0 + $1.count }
        if selected > 0 { right.append("\(selected) selected") }
        if options.showHidden { right.append("hidden") }
        right.append("\(current.entries.isEmpty ? 0 : current.cursor + 1)/\(current.entries.count)")
        status.right = right.joined(separator: "   ")
    }

    // MARK: Actions

    func open(_ e: FileEntry) {
        NSWorkspace.shared.open(URL(fileURLWithPath: join(cwd, e.name)))
    }

    func copy(_ target: Action.CopyTarget) {
        let names = selection[cwd].map { Array($0).sorted() } ?? current.hovered.map { [$0.name] } ?? []
        guard !names.isEmpty else { return }
        let strings: [String] = names.map { name in
            switch target {
            case .path: join(cwd, name)
            case .dir: cwd
            case .filename: name
            case .nameWithoutExt: (name as NSString).deletingPathExtension
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Array(NSOrderedSet(array: strings)).compactMap { $0 as? String }.joined(separator: "\n"), forType: .string)
    }

    /// yazi `remove`: Trash is reversible, so no prompt (Finder behaviour). Permanent delete asks first.
    /// The work runs off the main thread; the listing is force-reloaded afterwards (not left to FSEvents,
    /// which misses /tmp paths, see ROADMAP known issues).
    func remove(permanently: Bool) {
        let dir = cwd
        let names = targetNames()
        guard !names.isEmpty else { return }
        let paths = names.map { join(dir, $0) }
        let what = names.count == 1 ? "“\(names[0])”" : "\(names.count) items"
        visual = nil
        browserView.status.mode = "NOR"

        guard permanently else {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            NSWorkspace.shared.recycle(urls) { [weak self] trashed, error in
                let failures = urls.filter { trashed[$0] == nil }.map { url in
                    let name = url.lastPathComponent
                    return error.map { "\(name): \($0.localizedDescription)" } ?? name
                }
                Task { @MainActor in
                    self?.finishRemove(dir, failures, message: "Moved \(what) to Trash",
                                       title: "Some items couldn’t be moved to the Trash.")
                }
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete \(what) immediately?"
        alert.informativeText = (names.count > 1 ? names.prefix(8).joined(separator: "\n")
            + (names.count > 8 ? "\n…" : "") + "\n\n" : "") + "You can’t undo this action."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            runTask("Deleting \(what)", paths) { path in
                try FileManager.default.removeItem(atPath: path)
                return path
            } completion: { [weak self] _, failures in
                self?.finishRemove(dir, failures, message: "Deleted \(what)", title: "Some items couldn’t be deleted.")
            }
        }
    }

    func finishRemove(_ dir: String, _ failures: [String], message: String, title: String) {
        selection[dir] = nil
        if dir == cwd { browserView.currentList.setSelected([]) }
        load(dir, force: true)
        if let p = parentPath(dir) { load(p, force: true) }
        if failures.isEmpty { showFlash(message) } else { updateStatus(); reportFailures(failures, title: title) }
    }

    // MARK: Paths

    func normalize(_ p: String) -> String {
        var s = (p as NSString).expandingTildeInPath
        if !s.hasPrefix("/") { s = join(cwd, s) }
        return (s as NSString).standardizingPath
    }

    func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/" + name : dir + "/" + name }
    func parentPath(_ p: String) -> String? { p == "/" ? nil : (p as NSString).deletingLastPathComponent }
    func lastComponent(_ p: String) -> String { (p as NSString).lastPathComponent }
}
