import AppKit
import FMCore
import UniformTypeIdentifiers

/// Icons cached per type/extension; only app bundles get a per-path icon (their own artwork).
@MainActor
final class IconCache {
    static let shared = IconCache()

    private let workspace = NSWorkspace.shared
    private lazy var folder = workspace.icon(for: .folder)
    private lazy var generic = workspace.icon(for: .data)
    private lazy var executable = workspace.icon(for: .unixExecutable)
    private var byExtension: [String: NSImage] = [:]
    private var byPath: [String: NSImage] = [:]

    func icon(for e: FileEntry, in dir: String) -> NSImage {
        let ext = e.extensionLowercased
        if e.isDirectoryLike {
            if ext.isEmpty { return folder }
            if ext == "app" {
                let path = dir == "/" ? "/" + e.name : dir + "/" + e.name
                if let i = byPath[path] { return i }
                let i = workspace.icon(forFile: path)
                byPath[path] = i
                return i
            }
            let key = "/" + ext
            if let i = byExtension[key] { return i }
            let type = UTType(filenameExtension: ext, conformingTo: .directory)
            let i = type.map { $0.conforms(to: .package) ? workspace.icon(for: $0) : folder } ?? folder
            byExtension[key] = i
            return i
        }
        if ext.isEmpty { return e.isExecutable ? executable : generic }
        if let i = byExtension[ext] { return i }
        let i = UTType(filenameExtension: ext).map { workspace.icon(for: $0) } ?? generic
        byExtension[ext] = i
        return i
    }
}
