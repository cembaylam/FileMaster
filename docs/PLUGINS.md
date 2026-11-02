# Plugin system — native Swift bundles

See ADR-006.

## 1. Bundle format

```
MyPlugin.fmplugin/
└── Contents/
    ├── Info.plist          CFBundleIdentifier, NSPrincipalClass, FMPluginAPIVersion = "1.0",
    │                       FMPluginName, FMPluginCapabilities = [previewer, command, linemode, fetcher, opener]
    ├── MacOS/MyPlugin      Mach-O dylib (arm64), links @rpath/libFMPluginKit.dylib (NOT a static copy)
    └── Resources/          optional (default config, assets)
```

Search paths, in load order:
1. `FileMaster.app/Contents/PlugIns/` (built-in, shipped)
2. `~/Library/Application Support/FileMaster/Plugins/`
3. `~/.config/filemaster/plugins/` (handy for dotfiles)

If the same bundle ID appears twice, the later path wins (user overrides built-in).
Enable/disable and per-plugin config go in `filemaster.toml` under `[plugins.<bundle-id>]`.

## 2. ABI stability

- `FMPluginKit` is built as `.dynamic` with `-enable-library-evolution` and emits a `.swiftinterface`.
- `FMPluginAPIVersion` follows semver. The host loads a plugin if the **major** version matches and the plugin's minor ≤ host minor.
- Public SDK types are protocols and `final class`es / resilient structs. New requirements always come with default
  implementations in extensions so existing plugins keep loading.
- `make plugin-sdk` produces `build/PluginSDK/` (dylib + swiftinterface + swiftmodule + PluginTemplate) for building plugins
  outside this repo.

## 3. SDK surface (v1 draft)

```swift
// Entry point: NSPrincipalClass must subclass FMPluginBase
open class FMPluginBase: NSObject {
    public required override init()
    open func activate(host: FMHost) throws      // register capabilities here
    open func deactivate()
}

public protocol FMHost: Sendable {
    var apiVersion: SemanticVersion { get }
    func register(previewer: any Previewer)
    func register(command: PluginCommand)          // bindable action id "plugin.<id>.<name>"
    func register(linemode: any Linemode)
    func register(fetcher: any Fetcher)
    func register(opener: any Opener)
    @MainActor var app: FMAppContext { get }      // tabs, cwd, cursor, selection, navigate(), notify(), prompt()
    func config<T: Decodable>(_ type: T.Type) throws -> T?   // [plugins.<id>] table
    func log(_ message: String, level: LogLevel)
    func runTask(_ title: String, _ body: @Sendable @escaping (TaskProgress) async throws -> Void)
}

public protocol Previewer: Sendable {
    var id: String { get }
    var priority: Int { get }                      // higher wins; built-ins use 0…100
    var matches: PreviewMatch { get }              // UTTypes, globs, magic bytes, mime
    func makePreview(for file: FileInfo, context: PreviewContext) async throws -> PreviewContent
}

public enum PreviewContent: Sendable {
    case text(AttributedString)                    // host renders, selectable, scrollable
    case image(CGImage, caption: String?)
    case table(columns: [String], rows: [[String]])
    case keyValue([(String, String)])
    case hex(URL)                                  // hand off to the built-in hex view
    case view(@MainActor @Sendable () -> NSView)   // full custom AppKit view
    case delegate(to: String)                      // defer to another previewer id
}

public protocol Linemode: Sendable {              // extra column in the file list (like yazi linemode)
    var id: String { get }
    func text(for file: FileInfo) -> String       // must be fast (called during draw); precompute in a Fetcher
}

public protocol Fetcher: Sendable {               // async per-file metadata (git status, mime, tags…)
    var id: String { get }
    func fetch(_ files: [FileInfo], in dir: URL) async throws -> [FileID: FetchedValue]
}

public protocol Opener: Sendable {                // custom "open with" for matching files
    var matches: PreviewMatch { get }
    func open(_ files: [FileInfo], host: FMHost) async throws
}
```

Built-ins implemented against this API: every previewer in PREVIEW.md, the git status fetcher (M6), and the size/permissions/mtime linemodes.

## 4. Loader & safety

- Loading happens after the first frame on a background queue: `Bundle(url:)` → validate Info.plist and API version →
  `bundle.load()` → `principalClass as? FMPluginBase.Type` → `init()` → `activate(host:)` on main.
- **Crash sentinel:** before calling into a plugin (activate / preview / command), record `{pluginID, op}` in a small mmap'd
  file in Application Support and clear it afterwards. If we launch and find a stale sentinel, the app crashed inside that
  plugin. We disable it and tell the user.
- **Safe mode:** holding ⌥ during launch, or `--safe-mode`, loads no plugins.
- **Timeouts:** each previewer call runs with a deadline (default 2 s, configurable) and is cancelled after it. A plugin that
  keeps timing out gets its priority demoted for the session.
- Plugins can't be unloaded (dylibs can't be safely unloaded). Disabling one takes effect on the next launch.

## 5. Writing a plugin

```
cp -R build/PluginSDK/PluginTemplate MyPlugin && cd MyPlugin
swift build -c release && ./package.sh   # produces MyPlugin.fmplugin
cp -R MyPlugin.fmplugin ~/.config/filemaster/plugins/
```

An example plugin, `PluginsBuiltin/HelloPreviewer`, previews `.hello` files and is built by `make app` to keep the SDK path
under test.
