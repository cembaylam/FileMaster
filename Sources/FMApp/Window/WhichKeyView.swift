import AppKit

/// which-key popup: after a short pause in a multi-key sequence (`g`, `,`, `c`, `m`, `b`, `'`),
/// lists the possible continuations above the status bar. Display only.
@MainActor
final class WhichKeyView: NSVisualEffectView {
    private var entries: [(key: String, desc: String)] = []
    private let keyFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private let descFont = NSFont.systemFont(ofSize: 12)
    static let rowHeight: CGFloat = 20
    static let columnWidth: CGFloat = 260
    /// NSVisualEffectView doesn't run custom draw(_:); entries are drawn by this plain subview.
    private let canvas = Canvas()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        isHidden = true
        canvas.draw = { [weak self] in self?.drawEntries() }
        addSubview(canvas)
    }

    override func layout() {
        super.layout()
        canvas.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ entries: [(key: String, desc: String)]) {
        self.entries = entries
        isHidden = entries.isEmpty
        canvas.needsDisplay = true
    }

    /// Size for `width` available: as many columns as fit, rows filled top-down.
    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let cols = max(1, min(Int((maxWidth - 24) / Self.columnWidth), (entries.count + 3) / 4))
        let rows = (entries.count + cols - 1) / cols
        return NSSize(width: CGFloat(cols) * Self.columnWidth + 24, height: CGFloat(rows) * Self.rowHeight + 20)
    }

    private func drawEntries() {
        let cols = max(1, Int((bounds.width - 24) / Self.columnWidth))
        let rows = (entries.count + cols - 1) / cols
        for (i, e) in entries.enumerated() {
            let col = i / max(1, rows), row = i % max(1, rows)
            let x = 12 + CGFloat(col) * Self.columnWidth
            let y = 10 + CGFloat(row) * Self.rowHeight
            (Self.display(e.key) as NSString).draw(at: NSPoint(x: x, y: y + 2), withAttributes: [
                .font: keyFont, .foregroundColor: NSColor.controlAccentColor,
            ])
            (e.desc as NSString).draw(with: NSRect(x: x + 56, y: y + 2, width: Self.columnWidth - 64, height: 16),
                                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                      attributes: [.font: descFont, .foregroundColor: NSColor.labelColor])
        }
    }

    /// `<Space>` → ␣, `<D-1>` → ⌘1, etc. Shared with help.
    static func display(_ key: String) -> String {
        guard key.hasPrefix("<"), key.hasSuffix(">"), key.count > 2 else { return key }
        var body = String(key.dropFirst().dropLast())
        var mods = ""
        while body.count > 2, body.dropFirst().first == "-" {
            switch body.first! {
            case "C": mods += "⌃"
            case "A": mods += "⌥"
            case "S": mods += "⇧"
            case "D": mods += "⌘"
            default: break
            }
            body.removeFirst(2)
        }
        let names = ["Space": "␣", "Enter": "↩", "Esc": "⎋", "Tab": "⇥", "BackTab": "⇤", "Backspace": "⌫",
                     "Delete": "⌦", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "PageUp": "⇞",
                     "PageDown": "⇟", "Home": "↖", "End": "↘"]
        return mods + (names[body] ?? body)
    }
}

/// Flipped plain view that forwards drawing to a closure (content over visual-effect backgrounds).
@MainActor
final class Canvas: NSView {
    var draw: (() -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { draw?() }
}
