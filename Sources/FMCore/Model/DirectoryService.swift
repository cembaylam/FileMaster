import Darwin
import Synchronization

/// How a directory is presented: hidden filter + sort.
public struct ViewOptions: Sendable, Equatable {
    public var sort = SortOptions()
    public var showHidden = false
    public init() {}

    public func apply(_ raw: [FileEntry]) -> [FileEntry] {
        Sorter.sort(showHidden ? raw : raw.filter { !$0.isHidden }, sort)
    }
}

/// LRU cache of directory listings, shared by all windows. Freshness is checked against the directory's
/// mtime on every hit (one `stat`), so cached directories that aren't watched can't go stale on add/remove.
/// FSEvents-driven reloads pass `force` to catch in-place file changes too.
public final class DirectoryService: Sendable {
    public static let shared = DirectoryService()

    private struct Entry {
        var raw: [FileEntry]
        var stamp: DirStamp
        var options: ViewOptions
        var view: [FileEntry]
        var lastUse: UInt64
    }

    private struct State {
        var entries: [String: Entry] = [:]
        var clock: UInt64 = 0
    }

    private let state = Mutex(State())
    private let capacity: Int
    /// Re-sorting cached raw listings up to this size happens synchronously (no flicker on sort/hidden toggles).
    private let syncResortLimit = 5_000

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    /// Synchronous cache lookup for the main thread. Returns nil on a miss or a stale entry.
    public func cachedView(_ path: String, _ options: ViewOptions) -> [FileEntry]? {
        guard let stamp = DirStamp(path) else { return nil }
        return state.withLock { s -> [FileEntry]? in
            guard var e = s.entries[path], e.stamp == stamp else { return nil }
            if e.options != options {
                guard e.raw.count <= syncResortLimit else { return nil }
                e.view = options.apply(e.raw)
                e.options = options
            }
            s.clock += 1
            e.lastUse = s.clock
            s.entries[path] = e
            return e.view
        }
    }

    public func load(_ path: String, _ options: ViewOptions, force: Bool = false) async throws -> [FileEntry] {
        try await Task.detached(priority: .userInitiated) {
            try self.loadSync(path, options, force: force)
        }.value
    }

    public func loadSync(_ path: String, _ options: ViewOptions, force: Bool = false) throws -> [FileEntry] {
        // Stamp before listing: a change racing with the listing bumps mtime and invalidates us next time.
        let stamp = DirStamp(path) ?? DirStamp(sec: 0, nsec: 0)
        let cachedRaw: [FileEntry]? = force ? nil : state.withLock { s in
            s.entries[path].flatMap { $0.stamp == stamp ? $0.raw : nil }
        }
        let raw = try cachedRaw ?? DirLister.list(path)
        let view = options.apply(raw)
        state.withLock { s in
            s.clock += 1
            s.entries[path] = Entry(raw: raw, stamp: stamp, options: options, view: view, lastUse: s.clock)
            if s.entries.count > capacity, let victim = s.entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
                s.entries.removeValue(forKey: victim)
            }
        }
        return view
    }

    public func invalidate(_ path: String) {
        state.withLock { _ = $0.entries.removeValue(forKey: path) }
    }
}

struct DirStamp: Equatable, Sendable {
    let sec: Int
    let nsec: Int

    init(sec: Int, nsec: Int) {
        self.sec = sec
        self.nsec = nsec
    }

    init?(_ path: String) {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        sec = st.st_mtimespec.tv_sec
        nsec = st.st_mtimespec.tv_nsec
    }
}
