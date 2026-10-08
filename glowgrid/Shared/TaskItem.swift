import CoreGraphics
import Foundation

/// Tag colours. The first five raw values are the ones version 1.0 stored, so old data still reads.
enum TaskColor: String, Codable, CaseIterable, Identifiable {
    case sakura, crimson, persimmon, yuzu, matcha, mint, teal, sky, indigo, fuji, grape, cocoa, slate, sumi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sakura: return "樱花"
        case .crimson: return "茜红"
        case .persimmon: return "柿子"
        case .yuzu: return "柚子"
        case .matcha: return "抹茶"
        case .mint: return "薄荷"
        case .teal: return "青碧"
        case .sky: return "晴空"
        case .indigo: return "靛蓝"
        case .fuji: return "紫藤"
        case .grape: return "葡萄"
        case .cocoa: return "可可"
        case .slate: return "石青"
        case .sumi: return "墨色"
        }
    }
}

/// Decoration drawn on the right side of a tag, away from the text.
enum TaskPattern: String, Codable, CaseIterable, Identifiable {
    case solid, ribbon, stripes, dots, gradient, sparkle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "纯色"
        case .ribbon: return "彩带"
        case .stripes: return "斜纹"
        case .dots: return "圆点"
        case .gradient: return "渐变"
        case .sparkle: return "星光"
        }
    }
}

/// How a task's time is given.
enum TimeMode: String, CaseIterable, Identifiable {
    case deadline, start, range, allDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deadline: return "几点前"
        case .start: return "几点起"
        case .range: return "时间段"
        case .allDay: return "不定时"
        }
    }
}

/// One task. A single-day task has `endDay == nil`; a long task spans `day...endDay`.
struct TaskItem: Identifiable, Hashable {
    var id: UUID
    var title: String
    /// First day, "yyyy-MM-dd".
    var day: String
    /// Last day for long tasks.
    var endDay: String?
    /// Start time in minutes after midnight (on the first day).
    var start: Int?
    /// End / deadline time in minutes after midnight (on the last day).
    var due: Int?
    var color: TaskColor
    var pattern: TaskPattern
    var note: String
    /// The whole task is finished.
    var done: Bool
    /// Days a long task was checked in on.
    var checkins: [String]

    init(id: UUID = UUID(), title: String, day: String, endDay: String? = nil,
         start: Int? = nil, due: Int? = nil, color: TaskColor = .sky, pattern: TaskPattern = .solid,
         note: String = "", done: Bool = false, checkins: [String] = []) {
        self.id = id
        self.title = title
        self.day = day
        self.endDay = endDay
        self.start = start
        self.due = due
        self.color = color
        self.pattern = pattern
        self.note = note
        self.done = done
        self.checkins = checkins
    }
}

extension TaskItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, day, endDay, start, due, color, pattern, note, done, checkins
    }

    /// Tolerant decoding so files written by older versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        day = try c.decode(String.self, forKey: .day)
        endDay = try? c.decodeIfPresent(String.self, forKey: .endDay)
        start = try? c.decodeIfPresent(Int.self, forKey: .start)
        due = try? c.decodeIfPresent(Int.self, forKey: .due)
        let colorRaw = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? ""
        color = TaskColor(rawValue: colorRaw) ?? .sky
        let patternRaw = (try? c.decodeIfPresent(String.self, forKey: .pattern)) ?? ""
        pattern = TaskPattern(rawValue: patternRaw) ?? .solid
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
        checkins = (try? c.decodeIfPresent([String].self, forKey: .checkins)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(day, forKey: .day)
        try c.encodeIfPresent(endDay, forKey: .endDay)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeIfPresent(due, forKey: .due)
        try c.encode(color.rawValue, forKey: .color)
        try c.encode(pattern.rawValue, forKey: .pattern)
        try c.encode(note, forKey: .note)
        try c.encode(done, forKey: .done)
        try c.encode(checkins, forKey: .checkins)
    }
}

extension TaskItem {
    var isLong: Bool {
        guard let e = endDay else { return false }
        return e > day
    }

    var lastDay: String { isLong ? (endDay ?? day) : day }

    var mode: TimeMode {
        switch (start, due) {
        case (.some, .some): return .range
        case (.some, .none): return .start
        case (.none, .some): return .deadline
        default: return .allDay
        }
    }

    func covers(_ d: String) -> Bool { d >= day && d <= lastDay }

    var totalDays: Int { DayKey.days(from: day, to: lastDay) + 1 }

    /// 1-based index of `d` inside a long task.
    func dayIndex(_ d: String) -> Int { DayKey.days(from: day, to: d) + 1 }

    /// Minutes used to order tasks inside one day.
    var anchor: Int { start ?? due ?? 0 }

    func isCheckedIn(_ d: String) -> Bool { checkins.contains(d) }

    /// Not done and its end has passed.
    func isOverdue(today: String = DayKey.today(), nowMinutes: Double = DayKey.nowMinutes()) -> Bool {
        if done { return false }
        if lastDay < today { return true }
        if lastDay == today, let d = due, Double(d) <= nowMinutes { return true }
        return false
    }

    /// "14:00–16:30", "14:00 起", "12:00 前" (single-day tasks).
    var timeLabel: String {
        switch mode {
        case .range: return "\(DayKey.hm(start ?? 0))–\(DayKey.hm(due ?? 0))"
        case .start: return "\(DayKey.hm(start ?? 0)) 起"
        case .deadline: return "\(DayKey.hm(due ?? 0)) 前"
        case .allDay: return "全天"
        }
    }

    /// Compact version for the narrow month cells.
    var shortTimeLabel: String {
        switch mode {
        case .range: return "\(DayKey.hm(start ?? 0))-\(DayKey.hm(due ?? 0))"
        case .start: return "\(DayKey.hm(start ?? 0))起"
        case .deadline: return "\(DayKey.hm(due ?? 0))前"
        case .allDay: return ""
        }
    }

    /// Progress text for a long task on a given day: "第 5/20 天 · 18:00 截止".
    func longLabel(on d: String) -> String {
        var s = "第 \(dayIndex(d))/\(totalDays) 天"
        if d == day, let st = start { s += " · \(DayKey.hm(st)) 开始" }
        if d == lastDay, let du = due { s += " · \(DayKey.hm(du)) 截止" }
        else if d < lastDay {
            let left = DayKey.days(from: d, to: lastDay)
            s += " · 还剩 \(left) 天"
        }
        return s
    }

    /// One line used in notifications and summaries.
    func line(on d: String) -> String {
        isLong ? "\(title)（\(longLabel(on: d))）" : "\(timeLabel)　\(title)"
    }
}

extension Array where Element == TaskItem {
    /// Single-day tasks of one day, ordered by time.
    func on(_ day: String) -> [TaskItem] {
        filter { !$0.isLong && $0.day == day }.sorted { a, b in
            if a.anchor != b.anchor { return a.anchor < b.anchor }
            return (a.due ?? a.anchor) < (b.due ?? b.anchor)
        }
    }

    /// Long tasks running on that day.
    func longOn(_ day: String) -> [TaskItem] {
        filter { $0.isLong && $0.covers(day) }.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            return a.lastDay < b.lastDay
        }
    }
}

/// Rough text width: CJK counts as 1, Latin letters and digits as about half.
enum TextMetrics {
    static func units(_ s: String) -> CGFloat {
        s.unicodeScalars.reduce(CGFloat(0)) { $0 + ($1.value < 0x2E80 ? 0.55 : 1) }
    }
}
