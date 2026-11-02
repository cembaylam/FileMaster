/// fzf-like subsequence scoring for pickers (`Z`, `z`, `O`, help). Higher is better; nil = no match.
/// Case-insensitive for ASCII; bonuses for matches at word starts, after separators and consecutive runs.
public enum Fuzzy {
    public static func score(_ query: [UInt8], _ candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        var score = 0
        var qi = 0
        var prev: UInt8 = 0x2F // treat start as after "/"
        var run = 0
        var lastMatch = -1
        var i = 0
        for raw in candidate.utf8 {
            let c = lower(raw)
            if c == query[qi] {
                var s = 1
                if prev == 0x2F { s += 8 } // after /
                else if prev == 0x20 || prev == 0x5F || prev == 0x2D || prev == 0x2E { s += 6 } // space _ - .
                else if isLowerAlpha(lower(prev)) && raw >= 0x41 && raw <= 0x5A { s += 5 } // camelCase
                if lastMatch == i - 1 { run += 1; s += 3 * run } else { run = 0 }
                score += s
                lastMatch = i
                qi += 1
                if qi == query.count {
                    // Prefer shorter candidates and matches near the end (file name over directories).
                    return score * 4 - candidate.utf8.count / 8 + (lastSlash(candidate) < lastMatch ? 20 : 0)
                }
            }
            prev = raw
            i += 1
        }
        return nil
    }

    /// Query → folded bytes for `score`.
    public static func prepare(_ query: String) -> [UInt8] { query.utf8.filter { $0 != 0x20 }.map(lower) }

    @inline(__always) static func lower(_ c: UInt8) -> UInt8 { c >= 0x41 && c <= 0x5A ? c | 0x20 : c }
    @inline(__always) static func isLowerAlpha(_ c: UInt8) -> Bool { c >= 0x61 && c <= 0x7A }

    static func lastSlash(_ s: String) -> Int {
        var i = 0, last = -1
        for c in s.utf8 { if c == 0x2F { last = i }; i += 1 }
        return last
    }
}
