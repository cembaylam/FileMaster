import AppKit
import FMCore
import SwiftUI

/// ⌘, — SwiftUI is fine here: not on any hot path (CLAUDE.md). Writes Prefs and posts `Prefs.didChange`;
/// every open browser re-applies the options.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "FileMaster Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State private var options = Prefs.viewOptions
    @State private var linemode = Prefs.linemode
    @State private var fontSize = Double(PreviewFont.size)
    @State private var git = Prefs.showGitStatus
    @State private var restore = Prefs.restoreLastFolder

    var body: some View {
        Form {
            Section("Listing") {
                Toggle("Show hidden files", isOn: $options.showHidden)
                Toggle("Folders first", isOn: $options.sort.dirsFirst)
                Picker("Sort by", selection: $options.sort.by) {
                    ForEach(SortBy.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Reverse order", isOn: $options.sort.reverse)
                Picker("Info column", selection: $linemode) {
                    ForEach(Linemode.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                Toggle("Show Git status", isOn: $git)
            }
            Section("Preview") {
                Stepper("Text size: \(Int(fontSize)) pt", value: $fontSize, in: 9...28)
            }
            Section("Startup") {
                Toggle("Reopen the last folder", isOn: $restore)
            }
            Section("Keymap") {
                HStack {
                    Text("~/.config/filemaster/keymap.toml").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open") { Self.openKeymap() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onChange(of: options) { Prefs.viewOptions = options; changed() }
        .onChange(of: linemode) { Prefs.linemode = linemode; changed() }
        .onChange(of: git) { Prefs.showGitStatus = git; changed() }
        .onChange(of: restore) { Prefs.restoreLastFolder = restore }
        .onChange(of: fontSize) { PreviewFont.setSize(CGFloat(fontSize)) }
    }

    private func changed() { NotificationCenter.default.post(name: Prefs.didChange, object: nil) }

    static func name(_ m: Linemode) -> String {
        switch m {
        case .none: "None"
        case .size: "Size"
        case .permissions: "Permissions"
        case .mtime: "Date Modified"
        case .btime: "Date Created"
        case .owner: "Owner"
        }
    }

    /// Creates the file with a commented example on first use, then opens it in the default editor.
    static func openKeymap() {
        let url = KeymapConfig.defaultURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? """
            # FileMaster keymap (yazi format). Changes apply to new windows/tabs.
            # Commands: see Help (~ or F1). Keys: <C-x> ctrl, <A-x> option, <D-x> command, <S-x> shift.

            # [[manager.prepend_keymap]]
            # on   = ["g", "p"]
            # run  = "cd ~/Projects"
            # desc = "Go to Projects"

            """.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
