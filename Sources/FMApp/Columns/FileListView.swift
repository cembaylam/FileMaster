import AppKit
import FMCore

/// Custom-drawn file list (ADR-002): fixed row height, draws only dirty visible rows, cached CTLines,
/// icons cached per type. Scrolling is cursor-driven with yazi's `scrolloff`; no NSScrollView.
@MainActor
final class FileListView: NSView {
    static let rowHeight: CGFloat = 22

    private(set) var entries: [FileEntry] = []
    private(set) var cursor = 0
    private(set) var offset = 0
    private var selectedNames: Set<String> = []
    private var message: String?

    var dirPath = ""
    var isActive = true { didSet { if isActive != oldValue { needsDisplay = true } } }
    var showsCursor = true { didSet { if showsCursor != oldValue { needsDisplay = true } } }
    var linemode: Linemode = .size { didSet { if linemode != oldValue { needsDisplay = true } } }
    var scrolloff = 5
    /// Git status markers by entry name (M6); `gitAll` marks every entry (inside an untracked folder).
    private var gitMarks: [String: GitMark] = [:]
    private var gitAll: GitMark?

    func setGit(_ marks: [String: GitMark], all: GitMark?) {
        guard marks != gitMarks || all != gitAll else { return }
        gitMarks = marks
        gitAll = all
        needsDisplay = true
    }

    var onClick: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    /// If set, wheel scrolling is reported as row deltas (the current column moves its cursor);
    /// otherwise the view just scrolls itself.
    var onScrollRows: ((Int) -> Void)?
    private var scrollAccumulator: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize // redraw live on any size change (divider drag, window resize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var visibleRows: Int { max(1, Int(bounds.height / Self.rowHeight)) }

    func update(entries: [FileEntry], cursor: Int, selected: Set<String>, message: String?) {
        self.entries = entries
        self.cursor = entries.isEmpty ? 0 : min(max(0, cursor), entries.count - 1)
        self.selectedNames = selected
        self.message = message
        scrollToCursor()
        needsDisplay = true
    }

    func setSelected(_ selected: Set<String>) {
        guard selected != selectedNames else { return }
        selectedNames = selected
        needsDisplay = true
    }

    /// Cheap path for cursor moves: only the two affected rows are redrawn unless the view scrolls.
    func moveCursor(to index: Int) {
        guard !entries.isEmpty else { return }
        let old = cursor, oldOffset = offset
        cursor = min(max(0, index), entries.count - 1)
        scrollToCursor()
        if offset != oldOffset {
            needsDisplay = true
        } else {
            setNeedsDisplay(rowRect(old))
            setNeedsDisplay(rowRect(cursor))
        }
    }

    func scroll(by rows: Int) {
        let newOffset = min(max(0, offset + rows), max(0, entries.count - visibleRows))
        guard newOffset != offset else { return }
        offset = newOffset
        needsDisplay = true
    }

    private func scrollToCursor() {
        let vis = visibleRows
        let so = min(scrolloff, (vis - 1) / 2)
        if cursor < offset + so {
            offset = cursor - so
        } else if cursor > offset + vis - 1 - so {
            offset = cursor - (vis - 1 - so)
        }
        offset = max(0, min(offset, entries.count - vis))
    }

    func rowRect(_ i: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(i - offset) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scrollToCursor()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let text = TextCache.shared

        if entries.isEmpty {
            if let message {
                (message as NSString).draw(at: NSPoint(x: 14, y: 4), withAttributes: [
                    .font: text.nameFont, .foregroundColor: NSColor.secondaryLabelColor,
                ])
            }
            return
        }

        let rh = Self.rowHeight
        let first = offset + max(0, Int(dirtyRect.minY / rh))
        let last = min(entries.count - 1, offset + Int(dirtyRect.maxY / rh))
        guard first <= last else { return }

        let width = bounds.width
        let iconX: CGFloat = 12, nameX: CGFloat = 34
        let lmReserve: CGFloat = switch linemode {
        case .none: 0
        case .size: 64
        case .owner: 80
        case .permissions: 82
        case .mtime, .btime: 106
        }
        let gitReserve: CGFloat = gitMarks.isEmpty && gitAll == nil ? 0 : 16
        let nameBaseline = text.baseline(for: text.nameFont, rowHeight: rh)
        let metaBaseline = text.baseline(for: text.metaFont, rowHeight: rh)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let cursorFill = isActive ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor
        let icons = IconCache.shared

        for i in first...last {
            let e = entries[i]
            let y = CGFloat(i - offset) * rh
            let isCursor = showsCursor && i == cursor
            let emphasized = isCursor && isActive

            if isCursor {
                cursorFill.setFill()
                NSBezierPath(roundedRect: NSRect(x: 5, y: y + 0.5, width: width - 10, height: rh - 1), xRadius: 5, yRadius: 5).fill()
            }
            if selectedNames.contains(e.name) {
                (emphasized ? NSColor.white : NSColor.controlAccentColor).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1, y: y + 4, width: 3, height: rh - 8), xRadius: 1.5, yRadius: 1.5).fill()
            }

            icons.icon(for: e, in: dirPath).draw(in: NSRect(x: iconX, y: y + (rh - 16) / 2, width: 16, height: 16),
                                                 from: .zero, operation: .sourceOver, fraction: e.isHidden ? 0.55 : 1,
                                                 respectFlipped: true, hints: nil)

            let nameColor: NSColor = emphasized ? .alternateSelectedControlTextColor
                : e.isHidden ? .secondaryLabelColor
                : e.kind == .symlink ? .systemTeal
                : e.isExecutable ? .systemGreen
                : .labelColor
            ctx.setFillColor(nameColor.cgColor)
            let nameLine = text.line(e.name, font: .name, maxWidth: width - nameX - lmReserve - gitReserve - 10)
            ctx.textPosition = CGPoint(x: nameX, y: y + nameBaseline)
            CTLineDraw(nameLine, ctx)

            if let mark = gitAll ?? gitMarks[e.name] {
                let line = text.line(mark.letter, font: .meta, maxWidth: nil)
                ctx.setFillColor((emphasized ? NSColor.alternateSelectedControlTextColor : Self.gitColor(mark)).cgColor)
                ctx.textPosition = CGPoint(x: width - 14 - lmReserve - (linemode == .none ? 0 : 6) - 8, y: y + metaBaseline)
                CTLineDraw(line, ctx)
            }

            if linemode != .none {
                let s = linemode.text(for: e)
                if !s.isEmpty {
                    let line = text.line(s, font: .meta, maxWidth: nil)
                    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
                    ctx.setFillColor((emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor).cgColor)
                    ctx.textPosition = CGPoint(x: width - 14 - w, y: y + metaBaseline)
                    CTLineDraw(line, ctx)
                }
            }
        }
    }

    static func gitColor(_ m: GitMark) -> NSColor {
        switch m {
        case .modified, .renamed: .systemOrange
        case .added: .systemGreen
        case .untracked: .systemBlue
        case .deleted, .conflicted: .systemRed
        case .ignored: .tertiaryLabelColor
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = offset + Int(p.y / Self.rowHeight)
        guard i >= 0, i < entries.count else { return }
        if event.clickCount == 2 { onDoubleClick?(i) } else { onClick?(i) }
    }

    override func scrollWheel(with event: NSEvent) {
        var dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { dy *= Self.rowHeight }
        scrollAccumulator -= dy
        let rows = Int(scrollAccumulator / Self.rowHeight)
        if rows != 0 {
            scrollAccumulator -= CGFloat(rows) * Self.rowHeight
            if let onScrollRows { onScrollRows(rows) } else { scroll(by: rows) }
        }
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }
    }
}
