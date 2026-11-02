import Foundation
import FMCore

/// Persisted user preferences (UserDefaults). Key presses that change view options save here, so new
/// windows/tabs and the next launch start the same way. The Settings window edits the same values.
@MainActor
enum Prefs {
    static let didChange = Notification.Name("fm.prefsDidChange")
    private static let d = UserDefaults.standard

    static var viewOptions: ViewOptions {
        get {
            var o = ViewOptions()
            o.showHidden = d.bool(forKey: "fm.showHidden")
            if let s = d.string(forKey: "fm.sortBy"), let by = SortBy(rawValue: s) { o.sort.by = by }
            o.sort.reverse = d.bool(forKey: "fm.sortReverse")
            o.sort.dirsFirst = d.object(forKey: "fm.dirsFirst") as? Bool ?? true
            return o
        }
        set {
            d.set(newValue.showHidden, forKey: "fm.showHidden")
            d.set(newValue.sort.by.rawValue, forKey: "fm.sortBy")
            d.set(newValue.sort.reverse, forKey: "fm.sortReverse")
            d.set(newValue.sort.dirsFirst, forKey: "fm.dirsFirst")
        }
    }

    static var linemode: Linemode {
        get { d.string(forKey: "fm.linemode").flatMap(Linemode.init) ?? .size }
        set { d.set(newValue.rawValue, forKey: "fm.linemode") }
    }

    static var restoreLastFolder: Bool {
        get { d.object(forKey: "fm.restoreLastFolder") as? Bool ?? true }
        set { d.set(newValue, forKey: "fm.restoreLastFolder") }
    }

    static var showGitStatus: Bool {
        get { d.object(forKey: "fm.showGitStatus") as? Bool ?? true }
        set { d.set(newValue, forKey: "fm.showGitStatus") }
    }

    static var lastFolder: String? {
        get { d.string(forKey: "fm.lastFolder") }
        set { d.set(newValue, forKey: "fm.lastFolder") }
    }

    // MARK: Bookmarks (b<char> / '<char>)

    static var bookmarks: [String: String] {
        get { d.dictionary(forKey: "fm.bookmarks") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "fm.bookmarks") }
    }

    // MARK: Frecency (z): path → (visits, last visit)

    private static var frecencyCache: [String: [Double]]?

    static func recordVisit(_ path: String) {
        var f = frecencyCache ?? (d.dictionary(forKey: "fm.frecency") as? [String: [Double]] ?? [:])
        let now = Date().timeIntervalSince1970
        let old = f[path] ?? [0, now]
        f[path] = [old[0] + 1, now]
        if f.count > 1000 { // age out the weakest
            let keep = f.sorted { frecency($0.value, now) > frecency($1.value, now) }.prefix(800)
            f = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        frecencyCache = f
        d.set(f, forKey: "fm.frecency")
    }

    /// Folders by zoxide-style frecency, best first.
    static func frecentFolders() -> [String] {
        let f = frecencyCache ?? (d.dictionary(forKey: "fm.frecency") as? [String: [Double]] ?? [:])
        let now = Date().timeIntervalSince1970
        return f.sorted { frecency($0.value, now) > frecency($1.value, now) }.map(\.key)
    }

    private static func frecency(_ v: [Double], _ now: Double) -> Double {
        let age = now - (v.count > 1 ? v[1] : 0)
        let weight: Double = age < 3600 ? 4 : age < 86400 ? 2 : age < 604_800 ? 0.5 : 0.25
        return v[0] * weight
    }
}
