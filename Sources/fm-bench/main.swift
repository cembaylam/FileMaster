import Foundation
import FMCore

// Usage: fm-bench <dir> [--make N]
//   --make N  first create N empty files in <dir> (which must not exist yet) to benchmark huge dirs.

func measure(_ label: String, runs: Int = 7, _ body: () throws -> Int) rethrows {
    var best = Double.infinity
    var n = 0
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        n = try body()
        best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    print(String(format: "%-38@ %9.2f ms  (%d entries, best of %d)", label as NSString, best, n, runs))
}

var args = Array(CommandLine.arguments.dropFirst())
guard let dir = args.first else {
    print("usage: fm-bench <dir> [--make N]")
    exit(2)
}
if let i = args.firstIndex(of: "--make"), i + 1 < args.count, let n = Int(args[i + 1]) {
    guard !FileManager.default.fileExists(atPath: dir) else {
        print("refusing to --make into existing \(dir)")
        exit(1)
    }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for k in 0..<n {
        let fd = open("\(dir)/file_\(k).txt", O_CREAT | O_WRONLY, 0o644)
        close(fd)
    }
    print("created \(n) files in \(dir)")
}

let raw = try DirLister.list(dir)
try measure("DirLister.list (getattrlistbulk)") { try DirLister.list(dir).count }
try measure("FileManager + resourceValues", runs: 3) {
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: keys)
    var c = 0
    for u in urls { _ = try u.resourceValues(forKeys: Set(keys)); c += 1 }
    return c
}
measure("Sorter natural") { Sorter.sort(raw, SortOptions()).count }
measure("Sorter mtime") {
    var o = SortOptions()
    o.by = .modified
    return Sorter.sort(raw, o).count
}
var opts = ViewOptions()
measure("ViewOptions.apply (filter+natural)") { opts.apply(raw).count }
opts.showHidden = true
let service = DirectoryService()
try measure("DirectoryService cold (force)") { try service.loadSync(dir, opts, force: true).count }
measure("DirectoryService cachedView") { service.cachedView(dir, opts)?.count ?? -1 }
