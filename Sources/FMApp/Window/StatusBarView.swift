import AppKit

/// yazi-style status line: mode pill · permissions · size · mtime ……… pending keys · selection · n/N
@MainActor
final class StatusBarView: NSView {
    var left = "" { didSet { if left != oldValue { needsDisplay = true } } }
    var right = "" { didSet { if right != oldValue { needsDisplay = true } } }
    var mode = "NOR" { didSet { if mode != oldValue { needsDisplay = true } } }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let pillFont = NSFont.systemFont(ofSize: 10, weight: .bold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize // redraw live on any size change (divider drag, window resize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let pillAttrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: NSColor.white]
        let pillSize = (mode as NSString).size(withAttributes: pillAttrs)
        let pill = NSRect(x: 8, y: (bounds.height - 16) / 2, width: pillSize.width + 12, height: 16)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        (mode as NSString).draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + (16 - pillSize.height) / 2),
                                withAttributes: pillAttrs)

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let y = (bounds.height - font.boundingRectForFont.height) / 2 + 1
        (left as NSString).draw(at: NSPoint(x: pill.maxX + 10, y: y), withAttributes: attrs)
        let rw = (right as NSString).size(withAttributes: attrs).width
        (right as NSString).draw(at: NSPoint(x: bounds.width - rw - 12, y: y), withAttributes: attrs)
    }
}
