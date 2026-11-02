import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        openWindow(at: initialPath())
        NSApp.activate()
        #if DEBUG
        ScriptDriver.runIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func newWindow(_ sender: Any?) {
        let path = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.browser.cwd
        openWindow(at: path ?? NSHomeDirectory())
    }

    @objc func showSettings(_ sender: Any?) { SettingsWindow.show() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = TaskCenter.shared.running
        guard running > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(running) file operation\(running == 1 ? " is" : "s are") still running."
        alert.informativeText = "Quitting now stops \(running == 1 ? "it" : "them") partway."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway").hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    @discardableResult
    private func openWindow(at path: String, tabOf parent: NSWindow? = nil) -> BrowserWindowController {
        let wc = BrowserWindowController(path: path)
        wc.onClose = { [weak self, weak wc] in self?.windows.removeAll { $0 === wc } }
        wc.onNewTab = { [weak self, weak wc] path in
            guard let self, let w = wc?.window else { return }
            openWindow(at: path, tabOf: w)
        }
        windows.append(wc)
        if let parent, let w = wc.window {
            parent.addTabbedWindow(w, ordered: .above)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(wc.browser.view)
        } else {
            wc.showWindow(nil)
        }
        return wc
    }

    /// First non-flag argument that is an existing directory, else home.
    private func initialPath() -> String {
        for arg in CommandLine.arguments.dropFirst() where !arg.hasPrefix("-") {
            var isDir: ObjCBool = false
            let p = (arg as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { return p }
        }
        if Prefs.restoreLastFolder, let last = Prefs.lastFolder {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: last, isDirectory: &isDir), isDir.boolValue { return last }
        }
        return NSHomeDirectory()
    }
}
