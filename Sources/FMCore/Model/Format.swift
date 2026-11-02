import Darwin
import Synchronization

/// Allocation-light formatters for the hot path (no DateFormatter / ByteCountFormatter).
public enum Format {
    /// Decimal units like Finder: 999 B, 1.2 KB, 34 MB.
    public static func size(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
        var v = Double(bytes) / 1000
        var i = 0
        while v >= 999.95 && i < units.count - 1 { v /= 1000; i += 1 }
        if v < 10 {
            let tenths = Int((v * 10).rounded())
            return "\(tenths / 10).\(tenths % 10) \(units[i])"
        }
        return "\(Int(v.rounded())) \(units[i])"
    }

    public static func date(_ seconds: Double) -> String {
        var t = time_t(seconds)
        var tmv = tm()
        localtime_r(&t, &tmv)
        return "\(tmv.tm_year + 1900)-\(pad2(tmv.tm_mon + 1))-\(pad2(tmv.tm_mday)) \(pad2(tmv.tm_hour)):\(pad2(tmv.tm_min))"
    }

    public static func permissions(_ e: FileEntry) -> String {
        var s = [UInt8](repeating: UInt8(ascii: "-"), count: 10)
        switch e.kind {
        case .directory: s[0] = UInt8(ascii: "d")
        case .symlink: s[0] = UInt8(ascii: "l")
        case .other: s[0] = UInt8(ascii: "?")
        case .file: break
        }
        let rwx: [UInt8] = [UInt8(ascii: "r"), UInt8(ascii: "w"), UInt8(ascii: "x")]
        for i in 0..<9 where e.mode & (1 << (8 - i)) != 0 {
            s[1 + i] = rwx[i % 3]
        }
        return String(decoding: s, as: UTF8.self)
    }

    private static let userNames = Mutex<[UInt32: String]>([:])

    public static func user(_ uid: UInt32) -> String {
        if let n = userNames.withLock({ $0[uid] }) { return n }
        var pw = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buf = [CChar](repeating: 0, count: 1024)
        let name = getpwuid_r(uid, &pw, &buf, buf.count, &result) == 0 && result != nil
            ? String(cString: pw.pw_name) : String(uid)
        userNames.withLock { $0[uid] = name }
        return name
    }

    @inline(__always)
    private static func pad2(_ v: Int32) -> String { v < 10 ? "0\(v)" : "\(v)" }
}

/// Extra info column in the file list (yazi "linemode").
public enum Linemode: String, Sendable, CaseIterable {
    case none, size, permissions, mtime, btime, owner

    public func text(for e: FileEntry) -> String {
        switch self {
        case .none: ""
        case .size: e.isDirectoryLike ? "" : Format.size(e.size)
        case .permissions: Format.permissions(e)
        case .mtime: Format.date(e.modified)
        case .btime: Format.date(e.created)
        case .owner: Format.user(e.uid)
        }
    }
}
