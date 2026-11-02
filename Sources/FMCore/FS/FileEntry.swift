import Darwin

/// One directory entry. A plain value type so it can cross actors freely.
public struct FileEntry: Sendable, Hashable {
    public enum Kind: UInt8, Sendable {
        case file, directory, symlink, other
    }

    public let name: String
    public let kind: Kind
    public let size: Int64
    /// Seconds since 1970 (with nanosecond fraction).
    public let modified: Double
    public let created: Double
    /// Permission bits (`st_mode & 0o7777`).
    public let mode: UInt16
    public let uid: UInt32
    public let gid: UInt32
    /// BSD flags (`UF_HIDDEN`, …).
    public let flags: UInt32
    public let fileID: UInt64
    /// For symlinks: whether the target is a directory (resolved at listing time).
    public let targetIsDirectory: Bool

    public init(name: String, kind: Kind, size: Int64, modified: Double, created: Double, mode: UInt16,
                uid: UInt32, gid: UInt32, flags: UInt32, fileID: UInt64, targetIsDirectory: Bool) {
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.created = created
        self.mode = mode
        self.uid = uid
        self.gid = gid
        self.flags = flags
        self.fileID = fileID
        self.targetIsDirectory = targetIsDirectory
    }

    public var isDirectoryLike: Bool { kind == .directory || (kind == .symlink && targetIsDirectory) }

    public var isHidden: Bool { name.utf8.first == UInt8(ascii: ".") || flags & UInt32(UF_HIDDEN) != 0 }

    public var isExecutable: Bool { kind == .file && mode & 0o111 != 0 }

    /// Lowercased extension without the dot, or "" (a leading dot does not start an extension).
    public var extensionLowercased: String {
        let u = name.utf8
        guard let dot = u.lastIndex(of: UInt8(ascii: ".")), dot != u.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
}
