import Foundation

/// The five colours a task can carry. Names match the prototype's swatches.
enum TaskColor: String, Codable, CaseIterable, Identifiable {
    case sakura, matcha, sky, yuzu, fuji

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sakura: return "樱花"
        case .matcha: return "抹茶"
        case .sky: return "晴空"
        case .yuzu: return "柚子"
        case .fuji: return "紫藤"
        }
    }
}

/// One "do X before HH:MM" item.
struct TaskItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    /// Day key, "yyyy-MM-dd" in the phone's time zone.
    var day: String
    /// Deadline, minutes after midnight.
    var due: Int
    /// Optional start time, minutes after midnight. When set the task is drawn as a block.
    var start: Int?
    var color: TaskColor
    var note: String
    var done: Bool

    init(id: UUID = UUID(), title: String, day: String, due: Int, start: Int? = nil,
         color: TaskColor = .sky, note: String = "", done: Bool = false) {
        self.id = id
        self.title = title
        self.day = day
        self.due = due
        self.start = start
        self.color = color
        self.note = note
        self.done = done
    }

    /// Not done and the deadline has already passed.
    func isOverdue(today: String = DayKey.today(), nowMinutes: Double = DayKey.nowMinutes()) -> Bool {
        if done { return false }
        return day < today || (day == today && Double(due) <= nowMinutes)
    }
}

extension Array where Element == TaskItem {
    /// Tasks of one day, ordered by deadline (then start).
    func on(_ day: String) -> [TaskItem] {
        filter { $0.day == day }.sorted { a, b in
            if a.due != b.due { return a.due < b.due }
            return (a.start ?? 0) < (b.start ?? 0)
        }
    }
}
