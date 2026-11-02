import Foundation
import Testing
@testable import FMCore

@Suite struct DirListerTests {
    @Test func matchesFileManager() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(repeating: 7, count: 1234).write(to: dir.appendingPathComponent("a.bin"))
        try Data().write(to: dir.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("link").path, withDestinationPath: "sub")
        try "ü".write(to: dir.appendingPathComponent("ünïcødé.txt"), atomically: true, encoding: .utf8)

        let entries = try DirLister.list(dir.path)
        let expected = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(Set(entries.map(\.name)) == Set(expected))

        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
        #expect(byName["a.bin"]?.size == 1234)
        #expect(byName["a.bin"]?.kind == .file)
        #expect(byName["sub"]?.kind == .directory)
        #expect(byName["link"]?.kind == .symlink)
        #expect(byName["link"]?.isDirectoryLike == true)
        #expect(byName[".hidden"]?.isHidden == true)
        #expect(byName["a.bin"]!.modified > 1_700_000_000)
    }

    @Test func missingDirectoryThrows() {
        #expect(throws: DirLister.Failure.self) { try DirLister.list("/nonexistent-\(UUID().uuidString)") }
    }
}

@Suite struct SortTests {
    func entry(_ name: String, dir: Bool = false, size: Int64 = 0) -> FileEntry {
        FileEntry(name: name, kind: dir ? .directory : .file, size: size, modified: 0, created: 0, mode: 0o644,
                  uid: 0, gid: 0, flags: 0, fileID: 0, targetIsDirectory: false)
    }

    @Test func natural() {
        let names = ["file10", "file2", "File1", "file02b", "zeta", "Alpha"]
        let sorted = Sorter.sort(names.map { entry($0) }, SortOptions()).map(\.name)
        #expect(sorted == ["Alpha", "File1", "file2", "file02b", "file10", "zeta"])
    }

    @Test func dirsFirstSurvivesReverse() {
        var o = SortOptions()
        o.reverse = true
        let sorted = Sorter.sort([entry("a"), entry("d", dir: true), entry("b")], o).map(\.name)
        #expect(sorted == ["d", "b", "a"])
    }

    @Test func bySize() {
        var o = SortOptions()
        o.by = .size
        let sorted = Sorter.sort([entry("big", size: 10), entry("small", size: 1)], o).map(\.name)
        #expect(sorted == ["small", "big"])
    }
}

@Suite struct KeymapTests {
    @Test func sequences() {
        let k = KeyEngine(bindings: DefaultKeymap.manager)
        #expect(k.feed("j") == .action(.arrow(1)))
        #expect(k.feed("g") == .pending("g"))
        #expect(k.feed("g") == .action(.top))
        #expect(k.feed(",") == .pending(","))
        #expect(k.feed("M") == .action(.sort(.modified, reverse: true)))
        #expect(k.feed("g") == .pending("g"))
        #expect(k.feed("<Esc>") == .cancelled)
        #expect(k.feed("Ω") == .unbound)
    }

    @Test func commandParsing() {
        #expect(Action(command: "arrow -50%") == .arrowPage(-0.5))
        #expect(Action(command: "cd ~/Downloads") == .cd("~/Downloads"))
        #expect(Action(command: "linemode mtime") == .linemode(.mtime))
        #expect(Action(command: "bogus") == nil)
    }
}

@Suite struct FormatTests {
    @Test func sizes() {
        #expect(Format.size(999) == "999 B")
        #expect(Format.size(1_234) == "1.2 KB")
        #expect(Format.size(34_000_000) == "34 MB")
    }
}
