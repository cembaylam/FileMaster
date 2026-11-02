import AppKit

/// Programmatic main menu (no nib). Navigation items target the responder chain (BrowserView).
@MainActor
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let app = submenu(main, "FileMaster")
        app.addItem(withTitle: "About FileMaster", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide FileMaster", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit FileMaster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let backspace = String(Character(UnicodeScalar(NSBackspaceCharacter)!))
        let file = submenu(main, "File")
        file.addItem(withTitle: "New Window", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "New Tab", action: #selector(BrowserView.newTab(_:)), keyEquivalent: "t")
        file.addItem(withTitle: "New File or Folder…", action: #selector(BrowserView.newItem(_:)), keyEquivalent: "n")
            .keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        file.addItem(withTitle: "Open", action: #selector(BrowserView.openItem(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Open With…", action: #selector(BrowserView.openWith(_:)), keyEquivalent: "o")
            .keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Get Info", action: #selector(BrowserView.showInfo(_:)), keyEquivalent: "i")
        file.addItem(withTitle: "Rename…", action: #selector(BrowserView.renameItem(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Move to Trash", action: #selector(BrowserView.moveToTrash(_:)), keyEquivalent: backspace)
        file.addItem(withTitle: "Delete Immediately…", action: #selector(BrowserView.deleteImmediately(_:)),
                     keyEquivalent: backspace)
            .keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        file.addItem(withTitle: "Close Tab", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Search Names…", action: #selector(BrowserView.searchNames(_:)), keyEquivalent: "f")
        edit.addItem(withTitle: "Search Contents…", action: #selector(BrowserView.searchContents(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Filter…", action: #selector(BrowserView.filterItems(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .option]

        let view = submenu(main, "View")
        view.addItem(withTitle: "Show Hidden Files", action: #selector(BrowserView.toggleHiddenFiles(_:)), keyEquivalent: ".")
            .keyEquivalentModifierMask = [.command, .shift]
        view.addItem(.separator())
        // Viewer open: zoom the PDF/image; otherwise the preview text size (BrowserView.zoom).
        view.addItem(withTitle: "Actual Size", action: #selector(BrowserView.actualSizeText(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Zoom In", action: #selector(BrowserView.biggerText(_:)), keyEquivalent: "+")
        for alt in ["=", "*"] { // ⌘= without Shift like Safari; ⌘* on Turkish keyboards
            let item = view.addItem(withTitle: "Zoom In", action: #selector(BrowserView.biggerText(_:)), keyEquivalent: alt)
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        view.addItem(withTitle: "Zoom Out", action: #selector(BrowserView.smallerText(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        let go = submenu(main, "Go")
        go.addItem(withTitle: "Back", action: #selector(BrowserView.goBack(_:)), keyEquivalent: "[")
        go.addItem(withTitle: "Forward", action: #selector(BrowserView.goForward(_:)), keyEquivalent: "]")
        go.addItem(withTitle: "Enclosing Folder", action: #selector(BrowserView.goEnclosing(_:)),
                   keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        go.addItem(.separator())
        go.addItem(withTitle: "Home", action: #selector(BrowserView.goHome(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .shift]
        go.addItem(withTitle: "Downloads", action: #selector(BrowserView.goDownloads(_:)), keyEquivalent: "l")
            .keyEquivalentModifierMask = [.command, .option]
        go.addItem(.separator())
        go.addItem(withTitle: "Go to Folder…", action: #selector(BrowserView.goToFolder(_:)), keyEquivalent: "g")
            .keyEquivalentModifierMask = [.command, .shift]
        let goAlt = go.addItem(withTitle: "Go to Folder…", action: #selector(BrowserView.goToFolder(_:)), keyEquivalent: "l")
        goAlt.isHidden = true
        goAlt.allowsKeyEquivalentWhenHidden = true
        go.addItem(withTitle: "Recent Folders…", action: #selector(BrowserView.jumpRecent(_:)), keyEquivalent: "")
        go.addItem(withTitle: "Bookmarks…", action: #selector(BrowserView.showBookmarks(_:)), keyEquivalent: "")

        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Tasks", action: #selector(BrowserView.showTasks(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        let help = submenu(main, "Help")
        help.addItem(withTitle: "Keyboard Shortcuts", action: #selector(BrowserView.showHelp(_:)), keyEquivalent: "/")
            .keyEquivalentModifierMask = [.command, .shift]
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
