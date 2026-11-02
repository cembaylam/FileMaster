import Foundation

/// Background file operations (paste, delete, link) shared by all windows. `w` shows them; the status bar
/// shows the running count; quitting asks first while any are running.
@MainActor
final class TaskCenter {
    static let shared = TaskCenter()
    static let didChange = Notification.Name("fm.tasksDidChange")

    enum State: Equatable { case running(done: Int, total: Int), finished, failed(String) }

    struct Item: Identifiable {
        let id: Int
        let title: String
        var state: State
        let started = Date()
    }

    private(set) var items: [Item] = []
    private var nextID = 0

    var running: Int { items.filter { if case .running = $0.state { true } else { false } }.count }

    func start(_ title: String, total: Int) -> Int {
        nextID += 1
        items.append(Item(id: nextID, title: title, state: .running(done: 0, total: total)))
        if items.count > 50 { items.removeFirst(items.count - 50) }
        post()
        return nextID
    }

    func update(_ id: Int, _ state: State) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        post()
    }

    private func post() { NotificationCenter.default.post(name: Self.didChange, object: nil) }
}
