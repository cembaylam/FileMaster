import AppKit
import FMCore

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let browser: BrowserViewController
    var onClose: (() -> Void)?
    /// New tab next to this one, at the given folder (AppDelegate owns window controllers).
    var onNewTab: ((String) -> Void)?

    private static let backForwardID = NSToolbarItem.Identifier("fm.backForward")
    private static let hiddenID = NSToolbarItem.Identifier("fm.hidden")

    init(path: String) {
        browser = BrowserViewController(path: path)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 600, height: 300)
        window.toolbarStyle = .unified
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "fm.browser"
        window.contentViewController = browser
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "fm.browser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        if !window.setFrameUsingName("fm.browser") { window.center() }
        window.setFrameAutosaveName("fm.browser")

        browser.onPathChange = { [weak window] path in
            window?.title = path == "/" ? "/" : (path as NSString).lastPathComponent
            let home = NSHomeDirectory()
            window?.subtitle = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            window?.representedURL = URL(fileURLWithPath: path)
        }
        browser.onShowHiddenChange = { [weak self] showing in self?.reflectHidden(showing) }
        browser.onTabAction = { [weak self] action in self?.handleTab(action) }
        browser.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(browser.view)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillEnterFullScreen(_ notification: Notification) { browser.updateChrome(fullScreen: true) }
    func windowWillExitFullScreen(_ notification: Notification) { browser.updateChrome(fullScreen: false) }
    // AppKit can override toolbar visibility mid-transition; settle it once the animation ends.
    func windowDidEnterFullScreen(_ notification: Notification) { browser.updateChrome() }
    func windowDidExitFullScreen(_ notification: Notification) { browser.updateChrome() }

    func windowDidBecomeKey(_ notification: Notification) {
        // Tab switches keep each tab's own options; re-sync the toolbar toggle.
        reflectHidden(browser.showsHidden)
    }

    // MARK: Tabs (native window tabs)

    private func handleTab(_ action: Action) {
        guard let window else { return }
        let tabs = window.tabbedWindows ?? [window]
        let i = tabs.firstIndex(of: window) ?? 0
        switch action {
        case .tabNew:
            onNewTab?(browser.cwd)
        case let .tabSwitch(n):
            guard tabs.indices.contains(n) else { NSSound.beep(); return }
            tabs[n].makeKeyAndOrderFront(nil)
        case let .tabStep(d):
            guard tabs.count > 1 else { return }
            tabs[((i + d) % tabs.count + tabs.count) % tabs.count].makeKeyAndOrderFront(nil)
        case let .tabSwap(d):
            guard let group = window.tabGroup, tabs.indices.contains(i + d) else { return }
            group.removeWindow(window)
            group.insertWindow(window, at: i + d)
            window.makeKeyAndOrderFront(nil)
        case .tabClose:
            window.performClose(nil)
        default:
            break
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backForwardID, .flexibleSpace, Self.hiddenID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.backForwardID:
            let group = NSToolbarItemGroup(itemIdentifier: id,
                                           images: [NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                                    NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!],
                                           selectionMode: .momentary, labels: ["Back", "Forward"],
                                           target: self, action: #selector(backForward(_:)))
            group.isNavigational = true
            return group
        case Self.hiddenID:
            // A one-segment selectable group renders as a native toggle (highlighted while on).
            let group = NSToolbarItemGroup(itemIdentifier: id, images: [Self.hiddenSymbol(showing: browser.showsHidden)],
                                           selectionMode: .selectAny, labels: ["Hidden Files"],
                                           target: self, action: #selector(toggleHidden(_:)))
            group.label = "Hidden Files"
            group.toolTip = "Show Hidden Files (. or ⇧⌘.)"
            group.setSelected(browser.showsHidden, at: 0)
            hiddenItem = group
            return group
        default:
            return nil
        }
    }

    private weak var hiddenItem: NSToolbarItemGroup?

    /// Hierarchical rendering: when off, the eye is dimmed and only the slash is full strength; when on, a crisp eye
    /// (the group's selected state adds the highlight). `labelColor` adapts to light/dark.
    private static func hiddenSymbol(showing: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium, scale: .medium)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
        let name = showing ? "eye" : "eye.slash"
        return NSImage(systemSymbolName: name, accessibilityDescription: "Hidden Files")!.withSymbolConfiguration(config)!
    }

    private func reflectHidden(_ showing: Bool) {
        guard let item = hiddenItem else { return }
        item.subitems.first?.image = Self.hiddenSymbol(showing: showing)
        item.setSelected(showing, at: 0)
    }

    @objc private func toggleHidden(_ sender: NSToolbarItemGroup) {
        browser.perform(.toggleHidden)
    }

    @objc private func backForward(_ sender: NSToolbarItemGroup) {
        browser.perform(sender.selectedIndex == 0 ? .back : .forward)
    }
}
