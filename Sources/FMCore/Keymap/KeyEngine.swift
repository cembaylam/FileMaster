/// A key sequence bound to an action. Keys use yazi notation: `j`, `G`, `<Up>`, `<C-d>`, `<D-Up>`, `<Space>`.
public struct KeyBinding: Sendable {
    public let keys: [String]
    public let action: Action
    public let desc: String

    public init(_ keys: [String], _ action: Action, _ desc: String = "") {
        self.keys = keys
        self.action = action
        self.desc = desc
    }

    /// `"g g"` style, or a single token.
    public init?(on: String, run: String, desc: String = "") {
        guard let action = Action(command: run) else { return nil }
        self.init(on.split(separator: " ").map(String.init), action, desc)
    }
}

/// Trie-based multi-key dispatcher (`gg`, `,m`, `cc`). Not thread-safe; owned by the main actor.
public final class KeyEngine {
    public enum Outcome: Equatable {
        case action(Action)
        /// Waiting for more keys; payload is the sequence so far (for the status bar / which-key).
        case pending(String)
        /// A pending sequence was aborted.
        case cancelled
        case unbound
    }

    final class Node {
        var children: [String: Node] = [:]
        var action: Action?
        var desc = ""
    }

    private let root = Node()
    private var node: Node
    private var sequence: [String] = []

    public init(bindings: [KeyBinding]) {
        node = root
        for b in bindings { add(b) }
    }

    public func add(_ binding: KeyBinding) {
        var n = root
        for k in binding.keys {
            if let next = n.children[k] {
                n = next
            } else {
                let next = Node()
                n.children[k] = next
                n = next
            }
        }
        n.action = binding.action
        n.desc = binding.desc
    }

    public var isPending: Bool { !sequence.isEmpty }

    /// Whether `key` would do something right now (used to claim ⌘-key equivalents before the menu does).
    public func accepts(_ key: String) -> Bool { node.children[key] != nil }

    /// Continuations of the pending sequence: (key, description).
    public var choices: [(key: String, desc: String)] {
        node.children.map { ($0.key, $0.value.action != nil ? $0.value.desc : "…") }.sorted { $0.key < $1.key }
    }

    public func feed(_ key: String) -> Outcome {
        guard let next = node.children[key] else {
            let wasPending = isPending
            reset()
            return wasPending ? .cancelled : .unbound
        }
        if next.children.isEmpty {
            reset()
            return next.action.map(Outcome.action) ?? .unbound
        }
        node = next
        sequence.append(key)
        return .pending(sequence.joined())
    }

    public func reset() {
        node = root
        sequence.removeAll()
    }
}
