import AppKit

/// Root view: lays out parent | current | preview at the configured ratio plus the status bar,
/// and owns keyboard focus for the window.
@MainActor
final class BrowserView: NSView {
    weak var controller: BrowserViewController?

    let parentList = FileListView()
    let currentList = FileListView()
    let preview = PreviewPaneView()
    let status = StatusBarView()
    let viewer = ViewerView()
    let prompt = PromptView()
    let picker = PickerView()
    let whichKey = WhichKeyView()

    var isViewerOpen: Bool { !viewer.isHidden }

    /// Viewer in full screen: no status bar, viewer fills the view (the toolbar is hidden by the controller).
    var isImmersive = false {
        didSet {
            guard isImmersive != oldValue else { return }
            status.isHidden = isImmersive
            needsLayout = true
        }
    }

    func setViewerOpen(_ open: Bool) {
        viewer.isHidden = !open
        for v in [parentList, currentList, preview] as [NSView] { v.isHidden = open }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    static let defaultRatio: [CGFloat] = [1, 4, 3]
    private static let ratioKey = "fm.columnRatio"
    var ratio: [CGFloat] = BrowserView.defaultRatio { didSet { needsLayout = true } }
    static let statusHeight: CGFloat = 24
    static let topInset: CGFloat = 4
    private static let minColumnWidth: CGFloat = 80
    private static let dividerHitWidth: CGFloat = 4
    private var draggedDivider: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        if let saved = UserDefaults.standard.array(forKey: Self.ratioKey) as? [Double], saved.count == 3,
           saved.allSatisfy({ $0 > 0 }) {
            ratio = saved.map { CGFloat($0) }
        }
        for v in [parentList, currentList, preview, status, viewer, whichKey, prompt, picker] as [NSView] { addSubview(v) }
        parentList.isActive = false
        viewer.isHidden = true
        // Overlays hand keyboard focus back when they close.
        prompt.onEnd = { [weak self] in self?.restoreFocus() }
        picker.onEnd = { [weak self] in self?.restoreFocus() }
    }

    func restoreFocus() {
        guard !prompt.isActive, !picker.isActive else { return }
        window?.makeFirstResponder(self)
    }

    func showWhichKey(_ entries: [(key: String, desc: String)]) {
        whichKey.show(entries)
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        let b = bounds
        let sh = Self.statusHeight
        status.frame = NSRect(x: 0, y: 0, width: b.width, height: sh)
        let h = b.height - sh - Self.topInset
        if viewer.superview === self { // not while it lives in the fast full-screen window
            viewer.frame = isImmersive ? b : NSRect(x: 0, y: sh, width: b.width, height: b.height - sh)
        }
        prompt.frame = NSRect(x: 0, y: sh, width: b.width, height: PromptView.height)
        picker.frame = NSRect(x: 0, y: sh, width: b.width, height: b.height - sh)
        if !whichKey.isHidden {
            let size = whichKey.preferredSize(maxWidth: b.width - 24)
            whichKey.frame = NSRect(x: b.width - size.width - 12, y: sh + 8, width: size.width, height: size.height)
        }
        let total = ratio.reduce(0, +)
        var x: CGFloat = 0
        for (i, v) in ([parentList, currentList, preview] as [NSView]).enumerated() {
            let w = (b.width * ratio[i] / total).rounded()
            let width = i == 2 ? b.width - x : w
            v.frame = NSRect(x: x, y: sh, width: width, height: h)
            x += w
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Resizable columns

    private var dividerXs: [CGFloat] { [currentList.frame.minX, preview.frame.minX] }

    private func divider(at p: NSPoint) -> Int? {
        guard !isViewerOpen, p.y > Self.statusHeight else { return nil }
        return dividerXs.firstIndex { abs(p.x - $0) <= Self.dividerHitWidth }
    }

    /// Claim clicks on the divider strips before the column views get them.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if divider(at: convert(point, from: superview)) != nil { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        guard !isViewerOpen else { return }
        for x in dividerXs {
            addCursorRect(NSRect(x: x - Self.dividerHitWidth, y: Self.statusHeight,
                                 width: Self.dividerHitWidth * 2, height: bounds.height - Self.statusHeight),
                          cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let d = divider(at: convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 {
            ratio = Self.defaultRatio
            saveRatio()
        } else {
            draggedDivider = d
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = draggedDivider else { return }
        setDivider(d, to: convert(event.locationInWindow, from: nil).x)
    }

    /// Keyboard resize (⌃←/⌃→, ⌥←/⌥→): nudge a divider and save the ratio.
    func moveDivider(_ d: Int, by dx: CGFloat) {
        guard !isViewerOpen else { return }
        setDivider(d, to: dividerXs[d] + dx)
        saveRatio()
    }

    private func setDivider(_ d: Int, to x: CGFloat) {
        var w = [parentList.frame.width, currentList.frame.width, preview.frame.width]
        // Only the two columns adjacent to the divider change; the third keeps its width.
        let pair = w[d] + w[d + 1]
        let start = d == 0 ? 0 : w[0]
        w[d] = min(max(x - start, Self.minColumnWidth), pair - Self.minColumnWidth)
        w[d + 1] = pair - w[d]
        ratio = w
        layoutSubtreeIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        guard draggedDivider != nil else { return }
        draggedDivider = nil
        saveRatio()
    }

    private func saveRatio() {
        let total = ratio.reduce(0, +)
        UserDefaults.standard.set(ratio.map { Double($0 / total) }, forKey: Self.ratioKey)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        guard !isViewerOpen else { return }
        NSColor.separatorColor.setFill()
        for v in [currentList, preview] as [NSView] {
            NSRect(x: v.frame.minX - 0.5, y: v.frame.minY, width: 1, height: v.frame.height).fill()
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !handleKeyEvent(event) { super.keyDown(with: event) }
    }

    /// Shared with the fast full-screen window, which forwards its keys here.
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let token = KeyToken.from(event) else { return false }
        return controller?.handleKey(token) == true
    }

    /// Claim bound ⌘-keys (e.g. ⌘↑/⌘↓) before the menu sees them; unbound ones fall through to the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Zoom keys (⌘* is Turkish-keyboard zoom-in, it shares the + key), then bound ⌘-keys.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let token = KeyToken.from(event) else { return false }
        if let z = Self.zoomDirection(token) {
            zoom(z)
            return true
        }
        if token.contains("D-"), controller?.claimsKey(token) == true {
            return controller?.handleKey(token) ?? false
        }
        return false
    }

    /// Back from fast full screen: the viewer rejoins the view tree under the overlays.
    func reattachViewer(_ v: NSView) {
        addSubview(v, positioned: .below, relativeTo: whichKey)
        needsLayout = true
    }

    static func zoomDirection(_ token: String) -> Int? {
        switch token.replacingOccurrences(of: "S-", with: "") {
        case "<D-+>", "<D-=>", "<D-*>": 1
        case "<D-->": -1
        case "<D-0>": 0
        default: nil
        }
    }

    /// Viewer open → zoom the PDF/image (text: font size); otherwise the preview text size.
    func zoom(_ direction: Int) {
        if isViewerOpen {
            viewer.zoom(direction)
        } else {
            PreviewFont.setSize(direction == 0 ? PreviewFont.defaultSize : PreviewFont.size + CGFloat(direction))
        }
    }

    @objc func biggerText(_ sender: Any?) { zoom(1) }
    @objc func smallerText(_ sender: Any?) { zoom(-1) }
    @objc func actualSizeText(_ sender: Any?) { zoom(0) }

    // MARK: Menu actions (responder chain)

    @objc func goBack(_ sender: Any?) { controller?.perform(.back) }
    @objc func goForward(_ sender: Any?) { controller?.perform(.forward) }
    @objc func goEnclosing(_ sender: Any?) { controller?.perform(.leave) }
    @objc func goHome(_ sender: Any?) { controller?.perform(.cd("~")) }
    @objc func goDownloads(_ sender: Any?) { controller?.perform(.cd("~/Downloads")) }
    @objc func openItem(_ sender: Any?) { controller?.perform(.open) }
    @objc func moveToTrash(_ sender: Any?) { controller?.perform(.remove(permanently: false)) }
    @objc func copy(_ sender: Any?) { controller?.perform(.yank(cut: false)) }
    @objc func cut(_ sender: Any?) { controller?.perform(.yank(cut: true)) }
    @objc func paste(_ sender: Any?) { controller?.perform(.paste(overwrite: false)) }
    @objc override func selectAll(_ sender: Any?) { controller?.perform(.selectAll) }
    @objc func newItem(_ sender: Any?) { controller?.perform(.create) }
    @objc func renameItem(_ sender: Any?) { controller?.perform(.rename) }
    @objc func openWith(_ sender: Any?) { controller?.perform(.openWith) }
    @objc func goToFolder(_ sender: Any?) { controller?.perform(.cdPrompt) }
    @objc func searchNames(_ sender: Any?) { controller?.perform(.search(content: false)) }
    @objc func searchContents(_ sender: Any?) { controller?.perform(.search(content: true)) }
    @objc func filterItems(_ sender: Any?) { controller?.perform(.filter) }
    @objc func showInfo(_ sender: Any?) { controller?.perform(.info) }
    @objc func showTasks(_ sender: Any?) { controller?.perform(.tasks) }
    @objc func showHelp(_ sender: Any?) { controller?.perform(.help) }
    @objc func showBookmarks(_ sender: Any?) { controller?.perform(.markList) }
    @objc func jumpRecent(_ sender: Any?) { controller?.perform(.jump(fuzzy: false)) }
    @objc func newTab(_ sender: Any?) { controller?.perform(.tabNew) }
    @objc func deleteImmediately(_ sender: Any?) { controller?.perform(.remove(permanently: true)) }
    @objc func toggleHiddenFiles(_ sender: Any?) { controller?.perform(.toggleHidden) }
}
