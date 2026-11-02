import AppKit

/// CTLine cache for list rows. Lines take their color from the context fill color, so one cached line
/// serves every color state (cursor, hidden, symlink…).
@MainActor
final class TextCache {
    static let shared = TextCache()

    enum Font: UInt8 { case name, meta }

    let nameFont = NSFont.systemFont(ofSize: 13)
    let metaFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    private struct Key: Hashable {
        let string: String
        let font: Font
        let width: Int32 // -1 = untruncated
    }

    private var lines: [Key: CTLine] = [:]
    private lazy var ellipsis: [Font: CTLine] = [
        .name: CTLineCreateWithAttributedString(attributed("…", .name)),
        .meta: CTLineCreateWithAttributedString(attributed("…", .meta)),
    ]

    func line(_ s: String, font: Font, maxWidth: CGFloat?) -> CTLine {
        if lines.count > 20_000 { lines.removeAll(keepingCapacity: true) }
        let fullKey = Key(string: s, font: font, width: -1)
        let full: CTLine
        if let l = lines[fullKey] {
            full = l
        } else {
            full = CTLineCreateWithAttributedString(attributed(s, font))
            lines[fullKey] = full
        }
        guard let maxWidth, maxWidth > 0, CTLineGetTypographicBounds(full, nil, nil, nil) > maxWidth else { return full }
        let key = Key(string: s, font: font, width: Int32(maxWidth))
        if let l = lines[key] { return l }
        let truncated = CTLineCreateTruncatedLine(full, Double(maxWidth), .middle, ellipsis[font]) ?? full
        lines[key] = truncated
        return truncated
    }

    func baseline(for font: NSFont, rowHeight: CGFloat) -> CGFloat {
        ((rowHeight - (font.ascender - font.descender)) / 2 + font.ascender).rounded()
    }

    private func attributed(_ s: String, _ font: Font) -> CFAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: font == .name ? nameFont : metaFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
    }
}
