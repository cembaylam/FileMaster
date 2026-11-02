import Foundation

/// Loads `~/.config/filemaster/keymap.toml` (docs/KEYMAP.md). Only the subset of TOML the keymap needs:
/// `[[manager.keymap]]` / `[[manager.prepend_keymap]]` / `[[manager.append_keymap]]` tables with
/// `on` (string or array), `run` (string or array; first entry used) and `desc`. Other contexts are ignored for now.
public enum KeymapConfig {
    public struct Result: Sendable {
        public var bindings: [KeyBinding]
        public var errors: [String]
    }

    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/filemaster/keymap.toml")
    }

    /// Defaults merged with the user's file. Later bindings win in the KeyEngine trie, so the order is
    /// append → defaults → prepend (or just the user's `keymap` tables when present).
    public static func load(_ url: URL = defaultURL, defaults: [KeyBinding] = DefaultKeymap.manager) -> Result {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Result(bindings: defaults, errors: []) }
        return merge(parse(text), defaults: defaults)
    }

    static func merge(_ parsed: (tables: [String: [KeyBinding]], errors: [String]), defaults: [KeyBinding]) -> Result {
        let t = parsed.tables
        if let replace = t["manager.keymap"], !replace.isEmpty {
            return Result(bindings: replace, errors: parsed.errors)
        }
        return Result(bindings: (t["manager.append_keymap"] ?? []) + defaults + (t["manager.prepend_keymap"] ?? []),
                      errors: parsed.errors)
    }

    static func parse(_ text: String) -> (tables: [String: [KeyBinding]], errors: [String]) {
        var tables: [String: [KeyBinding]] = [:]
        var errors: [String] = []
        var table: String?
        var fields: [String: [String]] = [:]
        var tableLine = 0

        func flush() {
            guard let name = table else { return }
            defer { fields = [:] }
            guard let on = fields["on"], !on.isEmpty, let run = fields["run"]?.first else {
                errors.append("line \(tableLine): [[\(name)]] needs `on` and `run`")
                return
            }
            // `on = "g p"` is accepted as a sequence too.
            let keys = on.count == 1 ? on[0].split(separator: " ").map(String.init) : on
            guard let action = Action(command: run) else {
                errors.append("line \(tableLine): unknown command `\(run)`")
                return
            }
            tables[name, default: []].append(KeyBinding(keys, action, fields["desc"]?.first ?? run))
        }

        for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                flush()
                table = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                tableLine = n + 1
                continue
            }
            if line.hasPrefix("[") { flush(); table = nil; continue }
            guard table != nil, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard let strings = strings(in: value) else {
                errors.append("line \(n + 1): can't parse `\(value)`")
                continue
            }
            fields[key] = strings
        }
        flush()
        return (tables, errors)
    }

    /// `"a"` → ["a"]; `["a", "b"]` → ["a", "b"]. Basic and literal strings, `\"` and `\\` escapes.
    static func strings(in value: String) -> [String]? {
        var out: [String] = []
        var i = value.startIndex
        let isArray = value.hasPrefix("[")
        if isArray { i = value.index(after: i) }
        while i < value.endIndex {
            let c = value[i]
            if c == "\"" || c == "'" {
                var s = ""
                var j = value.index(after: i)
                while j < value.endIndex && value[j] != c {
                    if c == "\"" && value[j] == "\\", value.index(after: j) < value.endIndex {
                        j = value.index(after: j)
                    }
                    s.append(value[j])
                    j = value.index(after: j)
                }
                guard j < value.endIndex else { return nil }
                out.append(s)
                i = value.index(after: j)
                if !isArray { break }
            } else {
                i = value.index(after: i)
            }
        }
        return out.isEmpty ? nil : out
    }

    static func stripComment(_ line: Substring) -> Substring {
        var quote: Character?
        for i in line.indices {
            let c = line[i]
            if let q = quote { if c == q { quote = nil } } else if c == "\"" || c == "'" { quote = c } else if c == "#" {
                return line[..<i]
            }
        }
        return line
    }
}
