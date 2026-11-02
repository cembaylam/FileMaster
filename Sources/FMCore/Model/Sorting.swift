public enum SortBy: String, Sendable, CaseIterable {
    case natural, alphabetical, modified, created, `extension`, size
}

public struct SortOptions: Sendable, Equatable {
    public var by: SortBy = .natural
    public var reverse = false
    public var dirsFirst = true
    public init() {}
}

public enum Sorter {
    /// Sorts on precomputed ASCII-case-folded UTF-8 keys; `localizedStandardCompare` is too slow on 100k entries.
    public static func sort(_ entries: [FileEntry], _ options: SortOptions) -> [FileEntry] {
        let keys = entries.map(foldedKey)
        let exts: [ArraySlice<UInt8>] = options.by == .extension ? keys.map(extensionSlice) : []
        var order = Array(entries.indices)
        order.sort { a, b in
            let ea = entries[a], eb = entries[b]
            if options.dirsFirst {
                let da = ea.isDirectoryLike, db = eb.isDirectoryLike
                if da != db { return da }
            }
            var c: Int
            switch options.by {
            case .natural: c = naturalCompare(keys[a][...], keys[b][...])
            case .alphabetical: c = lexCompare(keys[a][...], keys[b][...])
            case .modified: c = compare(ea.modified, eb.modified)
            case .created: c = compare(ea.created, eb.created)
            case .size: c = compare(ea.size, eb.size)
            case .extension: c = lexCompare(exts[a], exts[b])
            }
            if c == 0 { c = naturalCompare(keys[a][...], keys[b][...]) }
            if c == 0 { c = compare(a, b) }
            return options.reverse ? c > 0 : c < 0
        }
        return order.map { entries[$0] }
    }

    @inline(__always)
    static func foldedKey(_ e: FileEntry) -> [UInt8] {
        e.name.utf8.map { $0 &- 65 < 26 ? $0 | 0x20 : $0 }
    }

    static func extensionSlice(_ key: [UInt8]) -> ArraySlice<UInt8> {
        guard let dot = key.lastIndex(of: UInt8(ascii: ".")), dot > 0 else { return [] }
        return key[(dot + 1)...]
    }

    @inline(__always)
    static func compare<T: Comparable>(_ a: T, _ b: T) -> Int { a < b ? -1 : (a > b ? 1 : 0) }

    static func lexCompare(_ a: ArraySlice<UInt8>, _ b: ArraySlice<UInt8>) -> Int {
        var i = a.startIndex, j = b.startIndex
        while i < a.endIndex && j < b.endIndex {
            if a[i] != b[j] { return a[i] < b[j] ? -1 : 1 }
            i += 1; j += 1
        }
        return compare(a.endIndex - i, b.endIndex - j)
    }

    /// Digit runs compare by numeric value ("file2" < "file10"); everything else bytewise.
    public static func naturalCompare(_ a: ArraySlice<UInt8>, _ b: ArraySlice<UInt8>) -> Int {
        @inline(__always) func isDigit(_ c: UInt8) -> Bool { c &- 48 < 10 }
        var i = a.startIndex, j = b.startIndex
        while i < a.endIndex && j < b.endIndex {
            let ca = a[i], cb = b[j]
            if isDigit(ca) && isDigit(cb) {
                var si = i; while si < a.endIndex && a[si] == 48 { si += 1 }
                var sj = j; while sj < b.endIndex && b[sj] == 48 { sj += 1 }
                var ei = si; while ei < a.endIndex && isDigit(a[ei]) { ei += 1 }
                var ej = sj; while ej < b.endIndex && isDigit(b[ej]) { ej += 1 }
                if ei - si != ej - sj { return ei - si < ej - sj ? -1 : 1 }
                var k = 0
                while k < ei - si {
                    if a[si + k] != b[sj + k] { return a[si + k] < b[sj + k] ? -1 : 1 }
                    k += 1
                }
                i = ei; j = ej
            } else {
                if ca != cb { return ca < cb ? -1 : 1 }
                i += 1; j += 1
            }
        }
        return compare(a.endIndex - i, b.endIndex - j)
    }
}
