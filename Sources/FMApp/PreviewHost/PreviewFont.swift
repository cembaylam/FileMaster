import AppKit

/// Font for text/hex previews: Fira Code (bundled in Contents/Resources/Fonts via ATSApplicationFontsPath),
/// falling back to SF Mono. Size is user-adjustable (View → Bigger/Smaller Text) and persisted.
@MainActor
enum PreviewFont {
    static let defaultSize: CGFloat = 13
    static let didChange = Notification.Name("fm.previewFontDidChange")
    private static let key = "fm.previewFontSize"

    private(set) static var size: CGFloat = {
        let s = UserDefaults.standard.double(forKey: key)
        return s > 0 ? clamp(s) : defaultSize
    }()
    private(set) static var regular = make(.regular)
    private(set) static var semibold = make(.semibold)

    static func setSize(_ s: CGFloat) {
        let s = clamp(s)
        guard s != size else { return }
        size = s
        regular = make(.regular)
        semibold = make(.semibold)
        UserDefaults.standard.set(Double(s), forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func clamp(_ s: CGFloat) -> CGFloat { min(max(s.rounded(), 9), 28) }

    private static func make(_ weight: NSFont.Weight) -> NSFont {
        NSFont(name: weight == .semibold ? "FiraCode-SemiBold" : "FiraCode-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
