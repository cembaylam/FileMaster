import Foundation

/// Recursive listing for name search / fuzzy find (`s`, `Z`). Breadth-first over `DirLister` (getattrlistbulk),
/// so shallow results arrive first. Skips package contents (.app, .photoslibrary, …), `node_modules` and,
/// unless `showHidden`, hidden entries — which also excludes `.git`.
public enum Walker {
    public struct Hit: Sendable, Hashable {
        /// Path relative to the walk root.
        public let path: String
        public let isDirectory: Bool
        public let size: Int64
    }

    static let skipNames: Set<String> = ["node_modules", ".git", ".Trash", ".DS_Store"]
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "musiclibrary", "xcarchive", "xcassets", "pkg", "plugin",
        "appex", "kext", "rtfd", "pages", "numbers", "key", "logicx", "fcpbundle", "imovielibrary", "dSYM",
    ]

    /// Calls `onBatch` roughly every `batch` hits. Stops early at `limit` hits or when the task is cancelled.
    public static func walk(_ root: String, showHidden: Bool, limit: Int = 500_000, batch: Int = 2000,
                            onBatch: ([Hit]) -> Void) {
        var queue: [String] = [""]
        var head = 0
        var pending: [Hit] = []
        pending.reserveCapacity(batch)
        var count = 0
        while head < queue.count {
            if Task.isCancelled { return }
            let rel = queue[head]
            head += 1
            let abs = rel.isEmpty ? root : (root == "/" ? "/" + rel : root + "/" + rel)
            guard let entries = try? DirLister.list(abs) else { continue }
            for e in entries {
                if skipNames.contains(e.name) || (!showHidden && e.isHidden) { continue }
                let path = rel.isEmpty ? e.name : rel + "/" + e.name
                let isDir = e.kind == .directory
                pending.append(Hit(path: path, isDirectory: isDir || e.isDirectoryLike, size: e.size))
                count += 1
                if isDir && !packageExtensions.contains(e.extensionLowercased) { queue.append(path) }
                if pending.count >= batch {
                    onBatch(pending)
                    pending.removeAll(keepingCapacity: true)
                }
                if count >= limit { onBatch(pending); return }
            }
            if head > 4096 { queue.removeFirst(head); head = 0 }
        }
        onBatch(pending)
    }

    /// Total size of regular files under `root` (info panel). Follows no symlinks.
    public static func totalSize(_ root: String) -> (bytes: Int64, files: Int) {
        var bytes: Int64 = 0, files = 0
        var stack = [root]
        while let dir = stack.popLast() {
            if Task.isCancelled { break }
            guard let entries = try? DirLister.list(dir) else { continue }
            for e in entries {
                if e.kind == .directory { stack.append(dir == "/" ? "/" + e.name : dir + "/" + e.name) }
                else if e.kind == .file { bytes += e.size; files += 1 }
            }
        }
        return (bytes, files)
    }
}
