import AppKit

/// Instant full screen for the viewer (`f`), like IINA/mpv's "non-native" mode: the viewer view moves into a
/// borderless window covering the screen, with menu bar and Dock hidden. No Space switch, no animation
/// (macOS native full screen takes ~0.7 s). Keys typed while it is key go to the owning BrowserView.
@MainActor
final class FastFullScreen {
    private let window: FullScreenWindow
    private let viewer: NSView
    private weak var home: BrowserView?
    private let savedOptions: NSApplication.PresentationOptions

    init(viewer: NSView, home: BrowserView) {
        self.viewer = viewer
        self.home = home
        savedOptions = NSApp.presentationOptions
        let screen = home.window?.screen ?? NSScreen.main!
        window = FullScreenWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        let container = FullScreenContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.home = home
        window.contentView = container

        // Keep the picture below the notch on MacBooks; the strip above stays black.
        let top = screen.safeAreaInsets.top
        viewer.removeFromSuperview()
        viewer.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: container.bounds.height - top)
        viewer.autoresizingMask = [.width, .height]
        container.addSubview(viewer)

        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(container)
    }

    /// Puts the viewer back into the browser window and restores the menu bar/Dock.
    func exit() {
        viewer.removeFromSuperview()
        viewer.autoresizingMask = []
        NSApp.presentationOptions = savedOptions
        if let home {
            home.reattachViewer(viewer)
            home.window?.makeKeyAndOrderFront(nil)
            home.window?.makeFirstResponder(home)
        }
        window.orderOut(nil)
    }
}

/// Borderless windows refuse key status by default.
private final class FullScreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Forwards keys to the BrowserView so the viewer keymap (Space, ←/→, 1–9, f, Esc, zoom…) keeps working.
private final class FullScreenContentView: NSView {
    weak var home: BrowserView?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if home?.handleKeyEvent(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        home?.handleKeyEquivalent(event) == true || super.performKeyEquivalent(with: event)
    }
}
