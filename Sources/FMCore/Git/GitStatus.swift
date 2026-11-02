import Foundation

/// Git status for list markers (M6). One `git status --porcelain -z` per repo, run off the main thread;
/// results are mapped onto a directory's entries by name, with folders aggregating their children.
public enum GitMark: UInt8, Sendable, Comparable {
    // Ordered by priority when aggregating into a folder.
    case ignored, untracked, modified, renamed, added, deleted, conflicted

    public static func < (a: GitMark, b: GitMark) -> Bool { a.rawValue < b.rawValue }

    public var letter: String {
        switch self {
        case .ignored: "!"
        case .untracked: "?"
        case .modified: "M"
        case .renamed: "R"
        case .added: "A"
        case .deleted: "D"
        case .conflicted: "U"
        }
    }
}

public enum GitStatus {
    public struct Snapshot: Sendable {
        public let root: String
        /// Repo-relative path → mark. Untracked/ignored folders end with "/".
        public let marks: [String: GitMark]

        /// Marks for the entries of `dir` (absolute, inside `root`), keyed by entry name. `all` is set when
        /// `dir` itself lies inside an untracked/ignored folder, so every entry shares that mark.
        public func marks(in dir: String) -> (byName: [String: GitMark], all: GitMark?) {
            let prefix: String
            if dir == root { prefix = "" } else if dir.hasPrefix(root + "/") {
                prefix = String(dir.dropFirst(root.count + 1)) + "/"
            } else { return ([:], nil) }
            var out: [String: GitMark] = [:]
            for (path, mark) in marks {
                if path.hasSuffix("/") && !prefix.isEmpty && prefix.hasPrefix(path) { return ([:], mark) }
                guard path.hasPrefix(prefix) else { continue }
                guard let first = path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first else { continue }
                let name = String(first)
                out[name] = max(out[name] ?? mark, mark)
            }
            return (out, nil)
        }
    }

    /// Nearest ancestor (or self) containing `.git`, or nil.
    public static func repoRoot(for dir: String) -> String? {
        var p = dir
        while true {
            if FileOps.exists(p == "/" ? "/.git" : p + "/.git") { return p }
            if p == "/" || p.isEmpty { return nil }
            p = (p as NSString).deletingLastPathComponent
        }
    }

    static let gitPath: String? = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Runs `git status`; nil if git is unavailable or fails. Blocking — call from a background task.
    public static func snapshot(root: String) -> Snapshot? {
        guard let git = gitPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        p.arguments = ["-C", root, "--no-optional-locks", "status", "--porcelain=v1", "-z", "--untracked-files=normal"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return Snapshot(root: root, marks: parse(data))
    }

    static func parse(_ data: Data) -> [String: GitMark] {
        var marks: [String: GitMark] = [:]
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var i = 0
        while i < records.count {
            let r = records[i]
            i += 1
            guard r.count > 3 else { continue }
            let x = r[r.startIndex], y = r[r.startIndex + 1]
            let path = String(decoding: r.dropFirst(3), as: UTF8.self)
            let mark: GitMark
            switch (x, y) {
            case (0x3F, 0x3F): mark = .untracked // ??
            case (0x21, 0x21): mark = .ignored // !!
            case (0x55, _), (_, 0x55), (0x41, 0x41), (0x44, 0x44): mark = .conflicted
            case (0x52, _):
                mark = .renamed
                i += 1 // rename records carry the old path as the next record
            case (0x41, _): mark = .added
            case (0x44, _), (_, 0x44): mark = .deleted
            default: mark = .modified
            }
            marks[path] = mark
        }
        return marks
    }
}
