import Foundation
import Testing
@testable import FMCore

@Suite struct FileOpsTests {
    func tempDir() throws -> String {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("fm-ops-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @Test func uniqueNames() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: d) }
        #expect(FileOps.uniqueName("a.txt", in: d) == "a.txt")
        FileManager.default.createFile(atPath: d + "/a.txt", contents: nil)
        FileManager.default.createFile(atPath: d + "/a_1.txt", contents: nil)
        #expect(FileOps.uniqueName("a.txt", in: d) == "a_2.txt")
        FileManager.default.createFile(atPath: d + "/.zshrc", contents: nil)
        #expect(FileOps.uniqueName(".zshrc", in: d) == ".zshrc_1")
    }

    @Test func transferCreateRenameLink() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: d) }
        try FileOps.create("src/", in: d)
        #expect(try FileOps.create("src/deep/x.txt", in: d) == "src")
        #expect(throws: FileOps.Failure.self) { try FileOps.create("src/", in: d) }
        #expect(throws: FileOps.Failure.self) { try FileOps.create("../escape", in: d) }
        try FileOps.create("dst/", in: d)

        let copied = try FileOps.transfer(d + "/src", into: d + "/dst", move: false, overwrite: false)
        #expect(FileOps.exists(copied + "/deep/x.txt"))
        let again = try FileOps.transfer(d + "/src", into: d + "/dst", move: false, overwrite: false)
        #expect((again as NSString).lastPathComponent == "src_1")
        #expect(throws: FileOps.Failure.self) { try FileOps.transfer(d + "/dst", into: d + "/dst/src", move: true, overwrite: false) }

        try FileOps.transfer(d + "/src", into: d + "/dst", move: true, overwrite: true)
        #expect(!FileOps.exists(d + "/src"))
        #expect(FileOps.exists(d + "/dst/src/deep/x.txt"))

        try FileOps.rename("dst", to: "Dst", in: d) // case-only
        #expect(try FileManager.default.contentsOfDirectory(atPath: d).contains("Dst"))
        try FileOps.create("other", in: d)
        #expect(throws: FileOps.Failure.self) { try FileOps.rename("other", to: "Dst", in: d) }

        let link = try FileOps.link(d + "/other", into: d + "/Dst")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == d + "/other")
    }
}

@Suite struct FuzzyTests {
    @Test func ranking() {
        let q = Fuzzy.prepare("bvc")
        #expect(Fuzzy.score(q, "Sources/BrowserViewController.swift") != nil)
        #expect(Fuzzy.score(q, "abc") == nil)
        let a = Fuzzy.score(Fuzzy.prepare("read"), "README.md")!
        let b = Fuzzy.score(Fuzzy.prepare("read"), "docs/rename/afterdark.txt")!
        #expect(a > b)
    }
}

@Suite struct GitTests {
    @Test func parseAndMap() {
        let raw = " M Sources/a.swift\0?? new/\0R  b2.txt\0b.txt\0A  Sources/x/y.swift\0UU c.txt\0"
        let marks = GitStatus.parse(Data(raw.utf8))
        #expect(marks["Sources/a.swift"] == .modified)
        #expect(marks["new/"] == .untracked)
        #expect(marks["b2.txt"] == .renamed)
        #expect(marks["b.txt"] == nil)
        #expect(marks["c.txt"] == .conflicted)
        let snap = GitStatus.Snapshot(root: "/r", marks: marks)
        let top = snap.marks(in: "/r")
        #expect(top.byName["Sources"] == .added) // added outranks modified
        #expect(top.byName["new"] == .untracked)
        #expect(snap.marks(in: "/r/new/inner").all == .untracked)
        #expect(snap.marks(in: "/elsewhere").byName.isEmpty)
    }
}

@Suite struct KeymapConfigTests {
    @Test func parseMerge() {
        let toml = """
        # comment
        [[manager.prepend_keymap]]
        on   = ["g", "p"]   # trailing comment
        run  = "cd ~/Projects"
        desc = "Go to Projects"

        [[manager.append_keymap]]
        on = "<C-p>"
        run = ["help"]

        [[manager.prepend_keymap]]
        on = "Q"
        run = "nonsense"
        """
        let parsed = KeymapConfig.parse(toml)
        #expect(parsed.errors.count == 1)
        let r = KeymapConfig.merge(parsed, defaults: DefaultKeymap.manager)
        #expect(r.bindings.last?.keys == ["g", "p"])
        #expect(r.bindings.last?.action == .cd("~/Projects"))
        #expect(r.bindings.first?.action == .help)
        let engine = KeyEngine(bindings: r.bindings)
        #expect(engine.feed("g") == .pending("g"))
        #expect(engine.feed("p") == .action(.cd("~/Projects")))
    }

    @Test func newCommands() {
        #expect(Action(command: "mark set a") == .markSet("a"))
        #expect(Action(command: "mark jump 7") == .markJump("7"))
        #expect(Action(command: "tab_switch 1 --relative") == .tabStep(1))
        #expect(Action(command: "tab_switch 3") == .tabSwitch(3))
        #expect(Action(command: "paste --force") == .paste(overwrite: true))
        #expect(Action(command: "search rg") == .search(content: true))
        #expect(Action(command: "visual_mode --unset") == .visual(unset: true))
        // Every default binding parses (KeyBinding init would have crashed otherwise) and `l` only enters.
        let engine = KeyEngine(bindings: DefaultKeymap.manager)
        #expect(engine.feed("<Right>") == .action(.enter))
        #expect(engine.feed("b") == .pending("b"))
        #expect(engine.feed("x") == .action(.markSet("x")))
    }
}
