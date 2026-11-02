import AppKit
import FMCore

/// File operations (M4): yank/cut/paste, symlink, create, rename, open with. Delete lives in the main file.
extension BrowserViewController {
    /// The yank register is shared by every tab and window, like yazi's.
    static var yanked: (paths: [String], cut: Bool)?
    /// Pasteboard change count right after our own yank: if it moved on, Finder (or anyone) copied since,
    /// and `p` pastes the pasteboard's file URLs instead.
    static var yankChangeCount = -1

    /// Selected names in cwd (sorted), else the hovered one.
    func targetNames() -> [String] {
        if let s = selection[cwd], !s.isEmpty { return s.sorted() }
        return current.hovered.map { [$0.name] } ?? []
    }

    func yank(cut: Bool) {
        let names = targetNames()
        guard !names.isEmpty else { return }
        let paths = names.map { join(cwd, $0) }
        Self.yanked = (paths, cut)
        // Also on the pasteboard, so ⌘V in Finder pastes a copy.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        Self.yankChangeCount = pb.changeCount
        visual = nil
        browserView.status.mode = "NOR"
        selection.removeAll()
        browserView.currentList.setSelected([])
        showFlash("\(cut ? "Cut" : "Yanked") \(names.count == 1 ? "“\(names[0])”" : "\(names.count) items")")
    }

    func unyank() {
        Self.yanked = nil
        updateStatus()
    }

    func paste(overwrite: Bool) {
        let pb = NSPasteboard.general
        let ours = Self.yanked.flatMap { pb.changeCount == Self.yankChangeCount ? $0 : nil }
        let move = ours?.cut ?? false
        let sources = (ours?.paths ?? (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []).map(\.path)).filter { FileOps.exists($0) }
        guard !sources.isEmpty else {
            NSSound.beep()
            return
        }
        let dir = cwd
        if move { Self.yanked = nil }
        let verb = move ? "Moving" : "Copying"
        let what = sources.count == 1 ? "“\((sources[0] as NSString).lastPathComponent)”" : "\(sources.count) items"
        runTask("\(verb) \(what) to \(abbreviate(dir))", sources) { src in
            try FileOps.transfer(src, into: dir, move: move, overwrite: overwrite)
        } completion: { [weak self] results, failures in
            guard let self else { return }
            if let first = results.first, dir == cwd { focusAfterReload((first as NSString).lastPathComponent) }
            if move { for src in Set(sources.map { ($0 as NSString).deletingLastPathComponent }) { dirs.invalidate(src) } }
            reportFailures(failures, title: "Some items couldn’t be \(move ? "moved" : "copied").")
        }
    }

    /// `-`: absolute symlinks to the yanked files in cwd.
    func link() {
        guard let y = Self.yanked, !y.paths.isEmpty else { NSSound.beep(); return }
        let dir = cwd
        runTask("Linking \(y.paths.count) item\(y.paths.count == 1 ? "" : "s")", y.paths) { src in
            try FileOps.link(src, into: dir)
        } completion: { [weak self] results, failures in
            if let first = results.first { self?.focusAfterReload((first as NSString).lastPathComponent) }
            self?.reportFailures(failures, title: "Some links couldn’t be created.")
        }
    }

    func create() {
        let dir = cwd
        browserView.prompt.begin("New file (end with / for a folder):") { [weak self] input in
            guard let self, !input.isEmpty else { return }
            do {
                let name = try FileOps.create(input, in: dir)
                if dir == cwd { focusAfterReload(name) }
            } catch {
                reportFailures([describe(error)], title: "Couldn’t create “\(input)”.")
            }
        }
    }

    func rename() {
        guard let e = current.hovered else { return }
        let dir = cwd, name = e.name
        // Cursor before the extension (yazi `rename --cursor=before_ext`): select the stem.
        let stem = e.isDirectoryLike && e.extensionLowercased != "app" ? name : (name as NSString).deletingPathExtension
        let stemLength = stem.isEmpty || stem == "." ? (name as NSString).length : (stem as NSString).length
        browserView.prompt.begin("Rename:", text: name, select: NSRange(location: 0, length: stemLength)) { [weak self] newName in
            guard let self, newName != name, !newName.isEmpty else { return }
            do {
                try FileOps.rename(name, to: newName, in: dir)
                if var s = selection[dir], s.remove(name) != nil { s.insert(newName); selection[dir] = s }
                if dir == cwd { focusAfterReload(newName) }
            } catch {
                reportFailures([describe(error)], title: "Couldn’t rename “\(name)”.")
            }
        }
    }

    /// `O`: choose an app for the hovered file (or the selection).
    func openWith() {
        let names = targetNames()
        guard let first = names.first else { return }
        let urls = names.map { URL(fileURLWithPath: join(cwd, $0)) }
        let ws = NSWorkspace.shared
        let defaultApp = ws.urlForApplication(toOpen: urls[0])
        var apps = ws.urlsForApplications(toOpen: urls[0])
        if let d = defaultApp { apps.removeAll { $0 == d }; apps.insert(d, at: 0) }
        let items = apps.map { app in
            PickerItem(title: FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""),
                       detail: app == defaultApp ? "default" : abbreviate((app.path as NSString).deletingLastPathComponent),
                       iconPath: app.path, payload: app.path)
        }
        let title = names.count == 1 ? "Open “\(first)” with" : "Open \(names.count) items with"
        browserView.picker.present(title, items: items) { item in
            let config = NSWorkspace.OpenConfiguration()
            ws.open(urls, withApplicationAt: URL(fileURLWithPath: item.payload), configuration: config)
        }
    }

    // MARK: Helpers

    /// Reload cwd and put the cursor on `name` once the new listing lands.
    func focusAfterReload(_ name: String) {
        current.pendingFocus = name
        load(cwd, force: true)
        if let p = parentPath(cwd) { load(p, force: true) }
    }

    /// Runs `op` for each source off the main thread, tracked in TaskCenter, then calls `completion` on main.
    func runTask(_ title: String, _ sources: [String], op: @escaping @Sendable (String) throws -> String,
                 completion: @escaping @MainActor ([String], [String]) -> Void) {
        let center = TaskCenter.shared
        let id = center.start(title, total: sources.count)
        Task.detached(priority: .userInitiated) {
            var results: [String] = [], failures: [String] = []
            for (i, src) in sources.enumerated() {
                do { results.append(try op(src)) } catch {
                    failures.append("\((src as NSString).lastPathComponent): \(describe(error))")
                }
                let done = i + 1
                await MainActor.run { center.update(id, .running(done: done, total: sources.count)) }
            }
            await MainActor.run {
                center.update(id, failures.isEmpty ? .finished : .failed(failures.joined(separator: "; ")))
                completion(results, failures)
            }
        }
    }

    func reportFailures(_ failures: [String], title: String) {
        guard !failures.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = failures.prefix(10).joined(separator: "\n")
            + (failures.count > 10 ? "\n… and \(failures.count - 10) more" : "")
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Error text without Foundation's "The operation couldn’t be completed." boilerplate where possible.
func describe(_ error: Error) -> String {
    if let f = error as? FileOps.Failure { return f.description }
    let ns = error as NSError
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
        return ns.localizedDescription + " (" + String(cString: strerror(Int32(underlying.code))) + ")"
    }
    return ns.localizedDescription
}
