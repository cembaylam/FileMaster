import Foundation

/// Synchronous file operations behind yank/paste, create, rename and link (docs/ARCHITECTURE.md §File ops).
/// Call them off the main thread. Copies go through `FileManager.copyItem`, which clones on APFS (copyfile
/// with COPYFILE_CLONE), so same-volume copies are O(1) per file.
public enum FileOps {
    public struct Failure: Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    /// `name`, or yazi-style `name_1.ext`, `name_2.ext`, … — the first that doesn't exist in `dir`.
    public static func uniqueName(_ name: String, in dir: String) -> String {
        guard exists(join(dir, name)) else { return name }
        let ns = name as NSString
        let isDotfile = name.hasPrefix(".") && !ns.deletingPathExtension.contains(".") && ns.pathExtension == ""
        let ext = isDotfile ? "" : ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        for i in 1... {
            let candidate = "\(stem)_\(i)" + (ext.isEmpty ? "" : ".\(ext)")
            if !exists(join(dir, candidate)) { return candidate }
        }
        fatalError("unreachable")
    }

    /// Copy or move `src` into `dir`. Without `overwrite`, an existing name gets a `_n` suffix.
    /// Returns the destination path.
    @discardableResult
    public static func transfer(_ src: String, into dir: String, move: Bool, overwrite: Bool) throws -> String {
        let name = (src as NSString).lastPathComponent
        let srcDir = (src as NSString).deletingLastPathComponent
        if isDescendant(dir, of: src) {
            throw Failure("“\(name)”: can’t put a folder inside itself")
        }
        // Moving onto itself is a no-op; copying onto itself makes a `_1` duplicate.
        if move && srcDir == dir { return src }
        let fm = FileManager.default
        var dstName = name
        if exists(join(dir, name)) {
            if overwrite && srcDir != dir {
                try fm.removeItem(atPath: join(dir, name))
            } else {
                dstName = uniqueName(name, in: dir)
            }
        }
        let dst = join(dir, dstName)
        if move { try fm.moveItem(atPath: src, toPath: dst) } else { try fm.copyItem(atPath: src, toPath: dst) }
        return dst
    }

    /// Absolute symlink to `target` inside `dir` (yazi `link`). Returns the link path.
    @discardableResult
    public static func link(_ target: String, into dir: String) throws -> String {
        let dst = join(dir, uniqueName((target as NSString).lastPathComponent, in: dir))
        try FileManager.default.createSymbolicLink(atPath: dst, withDestinationPath: target)
        return dst
    }

    /// yazi `create`: a trailing `/` makes a directory; intermediate directories are created as needed.
    /// Returns the first path component (the entry that appears in `dir`).
    @discardableResult
    public static func create(_ input: String, in dir: String) throws -> String {
        let isDir = input.hasSuffix("/")
        let rel = input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rel.isEmpty, !rel.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
            throw Failure("Invalid name")
        }
        let path = join(dir, rel)
        if exists(path) { throw Failure("“\(rel)” already exists") }
        let fm = FileManager.default
        if isDir {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        } else {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            guard fm.createFile(atPath: path, contents: nil) else { throw Failure(String(cString: strerror(errno))) }
        }
        return String(rel.split(separator: "/").first!)
    }

    /// Rename within `dir`. Case-only renames work on case-insensitive volumes (rename(2) handles them).
    public static func rename(_ name: String, to newName: String, in dir: String) throws {
        guard !newName.isEmpty, !newName.contains("/"), newName != ".", newName != ".." else {
            throw Failure("Invalid name")
        }
        guard newName != name else { return }
        let src = join(dir, name), dst = join(dir, newName)
        if exists(dst) && name.lowercased() != newName.lowercased() {
            throw Failure("“\(newName)” already exists")
        }
        if Darwin.rename(src, dst) != 0 { throw Failure(String(cString: strerror(errno))) }
    }

    // MARK: Helpers

    public static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    static func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/" + name : dir + "/" + name }
}
