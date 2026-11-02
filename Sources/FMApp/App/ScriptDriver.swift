#if DEBUG
import AppKit

/// Debug-only UI driver: replays key events from `FM_SCRIPT` through NSApp.sendEvent, so features can be
/// exercised (and screenshotted from outside) without Accessibility permission. Steps are separated by `|`:
///   `j`  `<Space>`  `<D-c>`  `<S-Down>`   one key (yazi notation)
///   `type:some text`                       types characters (into a prompt/picker field)
///   `sleep:500`                            waits (ms); every step also waits FM_SCRIPT_DELAY (default 250 ms)
/// Example: FM_SCRIPT='a|type:new.txt|<Enter>|sleep:800|r' build/FileMaster.app/Contents/MacOS/FileMaster ~/tmp
@MainActor
enum ScriptDriver {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let script = env["FM_SCRIPT"], !script.isEmpty else { return }
        let delay = Int(env["FM_SCRIPT_DELAY"] ?? "") ?? 250
        let steps = script.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            // Another instance may own activation; keep asking until our window is key (max ~5 s).
            for _ in 0..<50 where NSApp.keyWindow == nil {
                NSApp.activate()
                NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(100))
            }
            for step in steps {
                if step.hasPrefix("sleep:") {
                    try? await Task.sleep(for: .milliseconds(Int(step.dropFirst(6)) ?? 0))
                    continue
                }
                if step.hasPrefix("type:") {
                    for c in step.dropFirst(5) { send(String(c), keyCode: 0, mods: []) }
                } else {
                    key(step)
                }
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    private static func key(_ token: String) {
        guard token.hasPrefix("<"), token.hasSuffix(">"), token.count > 2 else {
            send(token, keyCode: 0, mods: [])
            return
        }
        var body = String(token.dropFirst().dropLast())
        var mods: NSEvent.ModifierFlags = []
        while body.count > 2, body.dropFirst().first == "-" {
            switch body.first! {
            case "C": mods.insert(.control)
            case "A": mods.insert(.option)
            case "S": mods.insert(.shift)
            case "D": mods.insert(.command)
            default: break
            }
            body.removeFirst(2)
        }
        func fn(_ k: Int) -> String { String(Character(UnicodeScalar(UInt32(k))!)) }
        let special: [String: (String, UInt16)] = [
            "Esc": ("\u{1b}", 53), "Enter": ("\r", 36), "Tab": ("\t", 48), "Space": (" ", 49),
            "Backspace": ("\u{7f}", 51), "Up": (fn(NSUpArrowFunctionKey), 126), "Down": (fn(NSDownArrowFunctionKey), 125),
            "Left": (fn(NSLeftArrowFunctionKey), 123), "Right": (fn(NSRightArrowFunctionKey), 124),
            "PageUp": (fn(NSPageUpFunctionKey), 116), "PageDown": (fn(NSPageDownFunctionKey), 121),
            "F1": (fn(NSF1FunctionKey), 122), "F2": (fn(NSF2FunctionKey), 120),
        ]
        if let (chars, code) = special[body] {
            send(chars, keyCode: code, mods: mods)
        } else {
            send(body, keyCode: 0, mods: mods)
        }
    }

    private static func send(_ chars: String, keyCode: UInt16, mods: NSEvent.ModifierFlags) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)
            else { continue }
            NSApp.sendEvent(e)
        }
    }
}
#endif
