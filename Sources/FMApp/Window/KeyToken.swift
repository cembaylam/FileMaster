import AppKit

/// NSEvent → yazi key notation (`j`, `G`, `<C-d>`, `<S-Up>`, `<D-Up>`, `<Space>`).
enum KeyToken {
    static func from(_ event: NSEvent) -> String? {
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])

        var special: String?
        if event.keyCode == 53 {
            special = "Esc"
        } else if let sk = event.specialKey {
            switch sk {
            case .upArrow: special = "Up"
            case .downArrow: special = "Down"
            case .leftArrow: special = "Left"
            case .rightArrow: special = "Right"
            case .pageUp: special = "PageUp"
            case .pageDown: special = "PageDown"
            case .home: special = "Home"
            case .end: special = "End"
            case .carriageReturn, .enter, .newline: special = "Enter"
            case .tab: special = "Tab"
            case .backTab: special = "BackTab"
            case .delete, .backspace: special = "Backspace"
            case .deleteForward: special = "Delete"
            case .f1: special = "F1"
            case .f2: special = "F2"
            default: return nil
            }
        } else if event.charactersIgnoringModifiers == " " {
            special = "Space"
        }

        if let special {
            return "<" + prefix(mods, includeShift: true) + special + ">"
        }

        if mods.isDisjoint(with: [.control, .option, .command]) {
            guard let c = event.characters, !c.isEmpty else { return nil }
            return c
        }
        guard let base = event.charactersIgnoringModifiers?.lowercased(), !base.isEmpty else { return nil }
        return "<" + prefix(mods, includeShift: true) + base + ">"
    }

    private static func prefix(_ mods: NSEvent.ModifierFlags, includeShift: Bool) -> String {
        var s = ""
        if mods.contains(.control) { s += "C-" }
        if mods.contains(.option) { s += "A-" }
        if mods.contains(.command) { s += "D-" }
        if includeShift && mods.contains(.shift) { s += "S-" }
        return s
    }
}
