import Foundation

/// Reads and writes all tasks as one JSON file in the shared container.
enum TaskStore {
    static var fileURL: URL { AppGroup.containerURL.appendingPathComponent("tasks.json") }

    static func load() -> [TaskItem] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([TaskItem].self, from: data)
        } catch {
            // Keep a copy of a file we could not read instead of silently overwriting it later.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("tasks-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: backup)
            return []
        }
    }

    static func save(_ tasks: [TaskItem]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Flip a task's done state.
    @discardableResult
    static func toggle(_ id: UUID) -> TaskItem? {
        var all = load()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        all[i].done.toggle()
        save(all)
        return all[i]
    }

    /// Flip a long task's check-in for one day.
    @discardableResult
    static func toggleCheckin(_ id: UUID, day: String) -> TaskItem? {
        var all = load()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        if let j = all[i].checkins.firstIndex(of: day) {
            all[i].checkins.remove(at: j)
        } else {
            all[i].checkins.append(day)
        }
        save(all)
        return all[i]
    }
}
