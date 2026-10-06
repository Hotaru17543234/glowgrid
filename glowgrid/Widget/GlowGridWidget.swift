import AppIntents
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let day: String
    let tasks: [TaskItem]
    var isSample = false
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), day: DayKey.today(), tasks: Self.sample(), isSample: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let entry = makeEntry(for: DayKey.today(), at: Date())
        if context.isPreview && entry.tasks.isEmpty {
            completion(TodayEntry(date: Date(), day: entry.day, tasks: Self.sample(), isSample: true))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let today = DayKey.today()
        let entry = makeEntry(for: today, at: now)
        let tomorrow = DayKey.add(today, days: 1)
        let midnight = DayKey.date(tomorrow)
        let midnightEntry = makeEntry(for: tomorrow, at: midnight)

        // Refresh again when the next deadline passes (so it turns red) or at midnight.
        let nowM = DayKey.nowMinutes()
        var next = midnight
        if let m = entry.tasks.filter({ !$0.done && Double($0.due) > nowM }).map({ $0.due }).min() {
            next = min(next, DayKey.dateAt(today, minutes: m).addingTimeInterval(30))
        }
        completion(Timeline(entries: [entry, midnightEntry], policy: .after(next)))
    }

    private func makeEntry(for day: String, at date: Date) -> TodayEntry {
        TodayEntry(date: date, day: day, tasks: TaskStore.load().on(day))
    }

    static func sample() -> [TaskItem] {
        let d = DayKey.today()
        return [
            TaskItem(title: "整理组会资料", day: d, due: 9 * 60 + 30, color: .sky, done: true),
            TaskItem(title: "取快递", day: d, due: 12 * 60, color: .yuzu),
            TaskItem(title: "写实验报告", day: d, due: 16 * 60 + 30, start: 14 * 60, color: .matcha),
            TaskItem(title: "买牛奶和鸡蛋", day: d, due: 19 * 60, color: .sakura)
        ]
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    private var ordered: [TaskItem] {
        entry.tasks.sorted { a, b in
            if a.done != b.done { return !a.done }
            return a.due < b.due
        }
    }

    var body: some View {
        let list = ordered
        let shown = Array(list.prefix(4))
        let doneCount = entry.tasks.filter { $0.done }.count
        let today = DayKey.today()
        let nowM = DayKey.nowMinutes()

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.day == today ? "今天" : "明天")
                    .font(.rounded(15, .bold))
                    .foregroundStyle(Palette.ink)
                Text("\(DayKey.md(entry.day)) 周\(DayKey.weekdayName(entry.day))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                if let h = JPHoliday.name(entry.day) {
                    Text(h)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.sun)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !entry.tasks.isEmpty {
                    ProgressRing(done: doneCount, total: entry.tasks.count)
                }
            }

            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("今天没有安排～")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("点这里添加一件事")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { t in
                    TaskRow(task: t,
                            overdue: !entry.isSample && t.isOverdue(today: today, nowMinutes: nowM),
                            interactive: !entry.isSample)
                }
                Spacer(minLength: 0)
                if list.count > 4 {
                    Text("还有 \(list.count - 4) 件")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .containerBackground(for: .widget) { Palette.sheet }
        .widgetURL(URL(string: entry.tasks.isEmpty ? "glowgrid://add" : "glowgrid://today"))
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let overdue: Bool
    let interactive: Bool

    var body: some View {
        HStack(spacing: 7) {
            if interactive {
                Button(intent: ToggleTaskIntent(taskID: task.id.uuidString)) {
                    check
                }
                .buttonStyle(.plain)
            } else {
                check
            }
            Circle()
                .fill(task.color.color)
                .frame(width: 7, height: 7)
            Text("\(DayKey.hm(task.due)) 前")
                .font(.rounded(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(overdue ? Palette.now : Palette.ink)
                .fixedSize()
            Text(task.title)
                .font(.system(size: 13))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? Palette.muted : Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(task.done ? 0.6 : 1)
        .frame(height: 22)
    }

    private var check: some View {
        ZStack {
            if task.done {
                Circle().fill(Palette.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.sheet)
            } else {
                Circle().stroke(Palette.ink.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .frame(width: 26, height: 22)
        .contentShape(Rectangle())
    }
}

private struct ProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Palette.line, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text("\(done)/\(total)")
                .font(.rounded(12, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
    }
}

@main
struct GlowGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GlowGridToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("萤格 · 今日清单")
        .description("今天要做的事，点小圆圈就能直接完成。")
        .supportedFamilies([.systemMedium])
    }
}
