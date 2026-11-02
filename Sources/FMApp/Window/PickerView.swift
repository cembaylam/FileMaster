import AppKit
import FMCore

/// One row in a picker. `payload` is whatever the caller needs back (a path, a binding index, …).
struct PickerItem: Sendable {
    var title: String
    var detail = ""
    /// SF Symbol shown before the title.
    var symbol: String?
    /// File whose Finder icon is shown instead of `symbol` (apps in "Open with").
    var iconPath: String?
    var payload = ""
    /// Text matched against the query; defaults to `title`.
    var matchText: String?
}

/// Command-palette style overlay (open with, help, bookmarks, search results, jump, tasks, info).
/// Type to filter (fuzzy, off the main thread for big lists); ↑/↓ ⌃n/⌃p move; Return picks; Esc closes.
/// `onQuery` switches it to caller-driven results (content search): the caller calls `setItems`.
@MainActor
final class PickerView: NSView, NSTextFieldDelegate {
    private let panel = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    let field = NSTextField()
    private let list = PickerListView()

    private var items: [PickerItem] = []
    private var filterTask: Task<Void, Never>?
    private var generation = 0
    private var onPick: ((PickerItem) -> Void)?
    private var onQuery: ((String) -> Void)?
    private var onClose: (() -> Void)?
    /// Called after the picker closes either way (BrowserView takes focus back).
    var onEnd: (() -> Void)?
    /// Shown in the count label while the caller is still producing items.
    var isLoading = false { didSet { updateCount() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 24
            s.shadowOffset = NSSize(width: 0, height: -8)
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }()
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        field.font = .systemFont(ofSize: 16)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        list.onClick = { [weak self] i in self?.list.select(i) }
        list.onDoubleClick = { [weak self] i in self?.list.select(i); self?.pick() }
        for v in [titleLabel, countLabel, field, list] as [NSView] { panel.addSubview(v) }
        addSubview(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isActive: Bool { !isHidden }
    override var isFlipped: Bool { true }

    /// Clicks outside the panel close the picker.
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { close() }
    }

    override func layout() {
        super.layout()
        let w = min(720, bounds.width - 48)
        let rows = CGFloat(min(14, max(list.count, 6)))
        let h = 72 + rows * PickerListView.rowHeight + 8
        panel.frame = NSRect(x: (bounds.width - w) / 2, y: min(80, bounds.height * 0.1), width: w,
                             height: min(h, bounds.height - 40))
        let pw = panel.bounds.width, ph = panel.bounds.height
        // panel isn't flipped: y grows upwards.
        titleLabel.frame = NSRect(x: 16, y: ph - 26, width: pw * 0.6, height: 16)
        countLabel.frame = NSRect(x: pw * 0.6, y: ph - 26, width: pw * 0.4 - 16, height: 16)
        field.frame = NSRect(x: 14, y: ph - 58, width: pw - 28, height: 24)
        list.frame = NSRect(x: 6, y: 6, width: pw - 12, height: ph - 72)
    }

    func present(_ title: String, placeholder: String = "Type to filter", items: [PickerItem], query: String = "",
                 onQuery: ((String) -> Void)? = nil, onClose: (() -> Void)? = nil,
                 onPick: @escaping (PickerItem) -> Void) {
        titleLabel.stringValue = title
        field.placeholderString = placeholder
        field.stringValue = query
        self.onPick = onPick
        self.onQuery = onQuery
        self.onClose = onClose
        self.items = items
        isLoading = false
        isHidden = false
        refilter()
        needsLayout = true
        window?.makeFirstResponder(field)
    }

    /// Replace (streaming searches) or extend the items; keeps the query and re-filters.
    func setItems(_ items: [PickerItem]) {
        self.items = items
        refilter()
    }

    func appendItems(_ more: [PickerItem]) {
        items.append(contentsOf: more)
        refilter()
    }

    /// Update one row in place (info panel's folder size).
    func updateItem(payload: String, detail: String) {
        guard let i = items.firstIndex(where: { $0.payload == payload }) else { return }
        items[i].detail = detail
        refilter()
    }

    func close() {
        guard isActive else { return }
        filterTask?.cancel()
        isHidden = true
        let closed = onClose
        onPick = nil
        onQuery = nil
        onClose = nil
        items = []
        list.setRows([], keepSelection: false)
        onEnd?()
        closed?()
    }

    private func pick() {
        guard let item = list.selectedItem, let pick = onPick else { return }
        close()
        pick(item)
    }

    private func updateCount() {
        countLabel.stringValue = (isLoading ? "searching…  " : "") + (items.isEmpty && !isLoading ? "" : "\(list.count)/\(items.count)")
    }

    private func refilter() {
        let query = onQuery == nil ? field.stringValue : ""
        filterTask?.cancel()
        generation &+= 1
        let gen = generation
        let items = self.items
        let keep = list.count > 0 && query == lastQuery
        lastQuery = query
        if query.isEmpty || items.count < 3000 {
            list.setRows(Self.filter(items, query), keepSelection: keep)
            updateCount()
            needsLayout = true
            return
        }
        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            let rows = Self.filter(items, query)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self, gen == self.generation else { return }
                self.list.setRows(rows, keepSelection: keep)
                self.updateCount()
                self.needsLayout = true
            }
        }
    }

    private var lastQuery = ""

    nonisolated static func filter(_ items: [PickerItem], _ query: String) -> [PickerItem] {
        let q = Fuzzy.prepare(query)
        if q.isEmpty { return items }
        var scored: [(Int, Int)] = []
        for (i, item) in items.enumerated() {
            if let s = Fuzzy.score(q, item.matchText ?? item.title) { scored.append((s, i)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return scored.prefix(2000).map { items[$0.1] }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        if let onQuery { onQuery(field.stringValue) } else { refilter() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): pick()
        case #selector(NSResponder.cancelOperation(_:)): close()
        case #selector(NSResponder.moveUp(_:)): list.move(-1)
        case #selector(NSResponder.moveDown(_:)): list.move(1)
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): list.move(-list.visibleRows)
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): list.move(list.visibleRows)
        case #selector(NSResponder.insertTab(_:)): list.move(1)
        case #selector(NSResponder.insertBacktab(_:)): list.move(-1)
        default: return false
        }
        return true
    }

    /// ⌃n / ⌃p, like yazi/fzf.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActive, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "n", "j": list.move(1); return true
        case "p", "k": list.move(-1); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Custom-drawn rows for the picker: icon · title · dimmed detail.
@MainActor
final class PickerListView: NSView {
    static let rowHeight: CGFloat = 28
    private var rows: [PickerItem] = []
    private var selected = 0
    private var offset = 0
    private var iconCache: [String: NSImage] = [:]
    var onClick: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    var count: Int { rows.count }
    var visibleRows: Int { max(1, Int(bounds.height / Self.rowHeight)) }
    var selectedItem: PickerItem? { rows.indices.contains(selected) ? rows[selected] : nil }

    func setRows(_ rows: [PickerItem], keepSelection: Bool) {
        self.rows = rows
        if !keepSelection { selected = 0; offset = 0 }
        selected = min(selected, max(0, rows.count - 1))
        clampOffset()
        needsDisplay = true
    }

    func select(_ i: Int) {
        guard !rows.isEmpty else { return }
        selected = min(max(0, i), rows.count - 1)
        clampOffset()
        needsDisplay = true
    }

    func move(_ d: Int) { select(selected + d) }

    private func clampOffset() {
        if selected < offset { offset = selected }
        if selected >= offset + visibleRows { offset = selected - visibleRows + 1 }
        offset = max(0, min(offset, rows.count - visibleRows))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampOffset()
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? Self.rowHeight : 1)
        offset = max(0, min(offset - Int(d.rounded()), rows.count - visibleRows))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let i = offset + Int(convert(event.locationInWindow, from: nil).y / Self.rowHeight)
        guard rows.indices.contains(i) else { return }
        if event.clickCount == 2 { onDoubleClick?(i) } else { onClick?(i) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rh = Self.rowHeight
        if rows.isEmpty {
            ("No results" as NSString).draw(at: NSPoint(x: 14, y: 6), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            return
        }
        let titleFont = NSFont.systemFont(ofSize: 13)
        let detailFont = NSFont.systemFont(ofSize: 11)
        let end = min(rows.count, offset + visibleRows + 1)
        for i in offset..<end {
            let item = rows[i]
            let y = CGFloat(i - offset) * rh
            let isSel = i == selected
            if isSel {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: 0, y: y + 1, width: bounds.width, height: rh - 2), xRadius: 6, yRadius: 6).fill()
            }
            var x: CGFloat = 10
            if let icon = icon(for: item) {
                icon.draw(in: NSRect(x: x, y: y + (rh - 18) / 2, width: 18, height: 18), from: .zero,
                          operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                x += 26
            }
            let titleColor: NSColor = isSel ? .alternateSelectedControlTextColor : .labelColor
            let detailColor: NSColor = isSel ? .alternateSelectedControlTextColor.withAlphaComponent(0.75) : .secondaryLabelColor
            let detailAttrs: [NSAttributedString.Key: Any] = [.font: detailFont, .foregroundColor: detailColor]
            let detailW = item.detail.isEmpty ? 0 : min((item.detail as NSString).size(withAttributes: detailAttrs).width,
                                                        bounds.width * 0.55)
            let titleRect = NSRect(x: x, y: y + (rh - 17) / 2, width: bounds.width - x - detailW - 24, height: 17)
            (item.title as NSString).draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                          attributes: [.font: titleFont, .foregroundColor: titleColor, .paragraphStyle: Self.truncMiddle])
            if detailW > 0 {
                (item.detail as NSString).draw(with: NSRect(x: bounds.width - detailW - 12, y: y + (rh - 14) / 2, width: detailW, height: 14),
                                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                               attributes: detailAttrs.merging([.paragraphStyle: Self.truncMiddle]) { $1 })
            }
        }
    }

    private static let truncMiddle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingMiddle
        return p
    }()

    private func icon(for item: PickerItem) -> NSImage? {
        if let path = item.iconPath {
            if let cached = iconCache[path] { return cached }
            let img = NSWorkspace.shared.icon(forFile: path)
            iconCache[path] = img
            return img
        }
        guard let symbol = item.symbol else { return nil }
        let key = "sf:" + symbol
        if let cached = iconCache[key] { return cached }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor])))
        iconCache[key] = img
        return img
    }
}
