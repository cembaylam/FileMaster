import CoreServices
import Foundation

/// FSEvents stream over the directories on screen. Delivers the set of changed paths (files and their
/// parent directories, no trailing slash) on a background queue; the owner hops to its own actor.
public final class FSWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (Set<String>) -> Void

    private let handler: Handler
    private let queue = DispatchQueue(label: "fm.fsevents", qos: .utility)
    // Mutated only on `queue`.
    private var stream: FSEventStreamRef?
    private var paths: [String] = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Replace the watched roots. Cheap to call on every navigation; no-ops if unchanged.
    public func watch(_ newPaths: [String]) {
        queue.async { [self] in
            guard newPaths != paths else { return }
            paths = newPaths
            restart()
        }
    }

    private func restart() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagFileEvents
                                             | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            var changed = Set<String>()
            for case let path as String in array.prefix(count) {
                let p = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
                changed.insert(p)
                changed.insert((p as NSString).deletingLastPathComponent)
            }
            watcher.handler(changed)
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }
}
