import Darwin

/// Lists a directory with `getattrlistbulk(2)`: names and all attributes we need come back in bulk,
/// a few syscalls for the whole directory instead of one-plus per entry (ADR-011).
public enum DirLister {
    public struct Failure: Error, CustomStringConvertible, Sendable {
        public let path: String
        public let code: Int32
        public var description: String { String(cString: strerror(code)) }
    }

    // <sys/attr.h> values. Defined here because some are too large for the imported Int32 macros.
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnCrTime: UInt32 = 0x0000_0200
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnOwnerID: UInt32 = 0x0000_8000
    private static let cmnGrpID: UInt32 = 0x0001_0000
    private static let cmnAccessMask: UInt32 = 0x0002_0000
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileDataLength: UInt32 = 0x0000_0200

    private static let vreg: UInt32 = 1, vdir: UInt32 = 2, vlnk: UInt32 = 5

    private static let bufferSize = 256 * 1024

    public static func list(_ path: String) throws -> [FileEntry] {
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw Failure(path: path, code: errno) }
        defer { Darwin.close(fd) }

        var request = attrlist(
            bitmapcount: UInt16(ATTR_BIT_MAP_COUNT), reserved: 0,
            commonattr: cmnReturnedAttrs | cmnName | cmnError | cmnObjType | cmnCrTime | cmnModTime
                | cmnOwnerID | cmnGrpID | cmnAccessMask | cmnFlags | cmnFileID,
            volattr: 0, dirattr: 0, fileattr: fileDataLength, forkattr: 0)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var result: [FileEntry] = []
        result.reserveCapacity(128)

        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure(path: path, code: errno)
            }
            if count == 0 { break }

            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<Int(count) {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let e = parse(entry, dirFD: fd) { result.append(e) }
                entry += length
            }
        }
        return result
    }

    /// Attributes are packed in bit order within each group (common, then file), each present only
    /// if its bit is set in the returned-attributes set. `ATTR_CMN_ERROR` immediately follows the set.
    @inline(__always)
    private static func parse(_ entry: UnsafeRawPointer, dirFD: Int32) -> FileEntry? {
        var p = entry + 4
        let common = p.loadUnaligned(as: UInt32.self)
        let fileAttrs = p.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
        p += 20 // attribute_set_t

        if common & cmnError != 0 {
            if p.loadUnaligned(as: UInt32.self) != 0 && common & cmnName == 0 { return nil }
            p += 4
        }

        var name = ""
        if common & cmnName != 0 {
            let offset = Int(p.loadUnaligned(as: Int32.self))
            let length = Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            name = String(decoding: UnsafeRawBufferPointer(start: p + offset, count: max(0, length - 1)), as: UTF8.self)
            p += 8
        } else {
            return nil
        }

        var objType: UInt32 = 0
        if common & cmnObjType != 0 { objType = p.loadUnaligned(as: UInt32.self); p += 4 }
        var created = 0.0
        if common & cmnCrTime != 0 { created = seconds(p); p += 16 }
        var modified = 0.0
        if common & cmnModTime != 0 { modified = seconds(p); p += 16 }
        var uid: UInt32 = 0
        if common & cmnOwnerID != 0 { uid = p.loadUnaligned(as: UInt32.self); p += 4 }
        var gid: UInt32 = 0
        if common & cmnGrpID != 0 { gid = p.loadUnaligned(as: UInt32.self); p += 4 }
        var mode: UInt32 = 0
        if common & cmnAccessMask != 0 { mode = p.loadUnaligned(as: UInt32.self); p += 4 }
        var flags: UInt32 = 0
        if common & cmnFlags != 0 { flags = p.loadUnaligned(as: UInt32.self); p += 4 }
        var fileID: UInt64 = 0
        if common & cmnFileID != 0 { fileID = p.loadUnaligned(as: UInt64.self); p += 8 }
        var size: Int64 = 0
        if fileAttrs & fileDataLength != 0 { size = p.loadUnaligned(as: Int64.self); p += 8 }

        let kind: FileEntry.Kind
        var targetIsDir = false
        switch objType {
        case vreg: kind = .file
        case vdir: kind = .directory
        case vlnk:
            kind = .symlink
            var st = stat()
            if fstatat(dirFD, name, &st, 0) == 0 { targetIsDir = (st.st_mode & S_IFMT) == S_IFDIR }
        default: kind = .other
        }

        return FileEntry(name: name, kind: kind, size: size, modified: modified, created: created,
                         mode: UInt16(truncatingIfNeeded: mode & 0o7777), uid: uid, gid: gid, flags: flags,
                         fileID: fileID, targetIsDirectory: targetIsDir)
    }

    @inline(__always)
    private static func seconds(_ p: UnsafeRawPointer) -> Double {
        Double(p.loadUnaligned(as: Int.self)) + Double(p.loadUnaligned(fromByteOffset: 8, as: Int.self)) / 1e9
    }
}
