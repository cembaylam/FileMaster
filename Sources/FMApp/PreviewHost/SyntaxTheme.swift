import AppKit
import FMPreview

/// Xcode-default-like palette, light/dark adaptive. (theme.toml overrides come with the config loader.)
@MainActor
enum SyntaxTheme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    private static let colors: [SyntaxKind: NSColor] = [
        .keyword: dynamic(0x9B2393, 0xFC5FA3),
        .constant: dynamic(0x9B2393, 0xFC5FA3),
        .type: dynamic(0x0B4F79, 0x5DD8FF),
        .string: dynamic(0xC41A16, 0xFC6A5D),
        .number: dynamic(0x1C00CF, 0xD0BF69),
        .comment: dynamic(0x5D6C79, 0x7F8C98),
        .tag: dynamic(0x0E5A9C, 0x67B7F7),
        .attribute: dynamic(0x815F03, 0xCC9768),
        .property: dynamic(0x326D74, 0x67B7A4),
        .variable: dynamic(0x6C36A9, 0xA167E6),
        .meta: dynamic(0x643820, 0xFD8F3F),
        .heading: dynamic(0x0E5A9C, 0x67B7F7),
        .inserted: dynamic(0x1E7B34, 0x7ED48B),
        .deleted: dynamic(0xB3261E, 0xFC6A5D),
    ]

    static func attributes(_ kind: SyntaxKind, base: NSFont) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.foregroundColor: colors[kind] ?? NSColor.labelColor]
        if kind == .keyword || kind == .heading {
            a[.font] = PreviewFont.semibold
        }
        if kind == .comment { // Fira Code has no italic; convert() then returns `base` unchanged.
            a[.font] = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }
        return a
    }
}
