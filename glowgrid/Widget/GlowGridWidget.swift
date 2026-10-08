import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let day: String
    let tasks: [TaskItem]
    let longs: [TaskItem]
    let pending: WidgetState.Pending?
    let pages: [String: Int]
    let bgID: String?
    let bg: BGSettings
    var isSample = false
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { Self.sampleEntry() }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let e = Self.makeEntry(at: Date(), all: TaskStore.load(), bg: BackgroundStore.load(),
                               pending: WidgetState.pending())
        if context.isPreview && e.tasks.isEmpty && e.longs.isEmpty {
            completion(Self.sampleEntry())
        } else {
            completion(e)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let all = TaskStore.load()
        let bg = BackgroundStore.load()
        let pending = WidgetState.pending(at: now)
        let today = DayKey.today()
        let midnight = DayKey.date(DayKey.add(today, days: 1))

        var dates: [Date] = [now, midnight]
        var pendingEnd: Date?
        if let p = pending {
            let end = p.at.addingTimeInterval(WidgetState.confirmWindow + 0.5)
            pendingEnd = end
            dates.append(end)
        }
        // Redraw when the next deadline passes, so it turns red.
        let nowM = DayKey.nowMinutes()
        let upcoming = all.on(today).filter { !$0.done }.compactMap { $0.due }.filter { Double($0) > nowM }
        if let m = upcoming.min() {
            dates.append(DayKey.dateAt(today, minutes: m).addingTimeInterval(30))
        }
        // Background slideshow: one entry per slot for the next ~12 hours.
        if bg.widgetEnabled && !bg.images.isEmpty {
            let step = Double(max(15, bg.widgetInterval)) * 60
            var t = (floor(now.timeIntervalSince1970 / step) + 1) * step
            var n = 0
            while n < 24 && t <= now.timeIntervalSince1970 + 12 * 3600 {
                dates.append(Date(timeIntervalSince1970: t))
                t += step
                n += 1
            }
        }

        let sorted = Array(Set(dates)).filter { $0 >= now }.sorted().prefix(40)
        let entries: [TodayEntry] = sorted.map { d in
            let p: WidgetState.Pending? = (pendingEnd.map { d < $0 } ?? false) ? pending : nil
            return Self.makeEntry(at: d, all: all, bg: bg, pending: p)
        }
        let reloadAt = sorted.last ?? midnight
        completion(Timeline(entries: entries, policy: .after(reloadAt)))
    }

    static func makeEntry(at date: Date, all: [TaskItem], bg: BGSettings, pending: WidgetState.Pending?) -> TodayEntry {
        let day = DayKey.key(date)
        let slot = Double(max(15, bg.widgetInterval)) * 60
        return TodayEntry(date: date,
                          day: day,
                          tasks: all.on(day),
                          longs: all.longOn(day),
                          pending: pending,
                          pages: ["medium": WidgetState.page("medium"), "large": WidgetState.page("large")],
                          bgID: bg.widgetEnabled ? bg.imageID(at: date, slotSeconds: slot) : nil,
                          bg: bg)
    }

    static func sampleEntry() -> TodayEntry {
        let d = DayKey.today()
        let tasks = [
            TaskItem(title: "整理组会资料", day: d, start: 8 * 60 + 30, due: 9 * 60 + 30, color: .sky, done: true),
            TaskItem(title: "取快递", day: d, due: 12 * 60, color: .yuzu, pattern: .ribbon),
            TaskItem(title: "写实验报告", day: d, start: 14 * 60, due: 16 * 60 + 30, color: .matcha, pattern: .stripes),
            TaskItem(title: "去图书馆自习", day: d, start: 19 * 60, color: .fuji, pattern: .sparkle)
        ]
        let long = TaskItem(title: "毕业论文初稿", day: DayKey.add(d, days: -4), endDay: DayKey.add(d, days: 15),
                            color: .persimmon, checkins: [DayKey.add(d, days: -4), DayKey.add(d, days: -2), DayKey.add(d, days: -1)])
        return TodayEntry(date: Date(), day: d, tasks: tasks, longs: [long], pending: nil,
                          pages: [:], bgID: nil, bg: BGSettings(), isSample: true)
    }
}

// MARK: - Rows

enum WRow: Identifiable {
    case long(TaskItem)
    case single(TaskItem)

    var task: TaskItem {
        switch self {
        case .long(let t), .single(let t): return t
        }
    }

    var isLong: Bool {
        if case .long = self { return true }
        return false
    }

    var id: String { task.id.uuidString }
}

enum WidgetLayout {
    static let checkW: CGFloat = 24
    static let timeW: CGFloat = 44
    static let bulletW: CGFloat = 12
    static let railW: CGFloat = 16
    static let rowSpacing: CGFloat = 4

    static func textWidth(total: CGFloat, rail: Bool) -> CGFloat {
        let fixed: CGFloat = checkW + timeW + bulletW + 12
        let railPart: CGFloat = rail ? railW + 4 : 0
        return total - fixed - railPart
    }

    static func rowHeight(_ r: WRow, textW: CGFloat) -> CGFloat {
        let t = r.task
        let perLine = max(1, floor(textW / 13.5))
        let lines = max(1, ceil(TextMetrics.units(t.title) / perLine))
        let textH = lines * 17 + (r.isLong ? 11 : 0)
        let timeH: CGFloat = (!r.isLong && t.mode == .range) ? 42 : 30
        return max(textH, timeH) + 4
    }

    /// Split rows into pages that each fit `height`.
    static func paginate(_ rows: [WRow], height: CGFloat, textW: CGFloat) -> [[WRow]] {
        var pages: [[WRow]] = []
        var cur: [WRow] = []
        var used: CGFloat = 0
        for r in rows {
            let h = rowHeight(r, textW: textW)
            if !cur.isEmpty && used + rowSpacing + h > height {
                pages.append(cur)
                cur = []
                used = 0
            }
            used += (cur.isEmpty ? 0 : rowSpacing) + h
            cur.append(r)
        }
        if !cur.isEmpty { pages.append(cur) }
        return pages
    }
}

// MARK: - Views

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var familyKey: String { family == .systemLarge ? "large" : "medium" }

    var body: some View {
        GeometryReader { geo in
            WidgetContent(entry: entry, familyKey: familyKey, size: geo.size)
        }
        .containerBackground(for: .widget) {
            WidgetBackground(entry: entry, target: family == .systemLarge ? .large : .medium)
        }
        .widgetURL(URL(string: entry.tasks.isEmpty && entry.longs.isEmpty ? "glowgrid://add" : "glowgrid://today"))
    }
}

struct WidgetBackground: View {
    let entry: TodayEntry
    let target: BGTarget

    var body: some View {
        ZStack {
            Palette.sheet
            if let id = entry.bgID, let ui = BackgroundStore.image(id, target) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .id(id)
                    .transition(entry.bg.effect.widgetTransition)
                Palette.sheet.opacity(entry.bg.dim)
            }
        }
    }
}

struct WidgetContent: View {
    let entry: TodayEntry
    let familyKey: String
    let size: CGSize

    private var rows: [WRow] {
        let longs = entry.longs.sorted { a, b in a.done != b.done ? !a.done : a.lastDay < b.lastDay }
        let singles = entry.tasks.sorted { a, b in
            if a.done != b.done { return !a.done }
            return a.anchor < b.anchor
        }
        return longs.map { WRow.long($0) } + singles.map { WRow.single($0) }
    }

    var body: some View {
        let all = rows
        let headerH: CGFloat = 22
        let listH = max(30, size.height - headerH - 6)
        let noRail = WidgetLayout.paginate(all, height: listH, textW: WidgetLayout.textWidth(total: size.width, rail: false))
        let needRail = noRail.count > 1
        let pages = needRail
            ? WidgetLayout.paginate(all, height: listH, textW: WidgetLayout.textWidth(total: size.width, rail: true))
            : noRail
        let page = min(entry.pages[familyKey] ?? 0, max(0, pages.count - 1))
        let nowM = Double(DayKey.minutes(of: entry.date))

        VStack(alignment: .leading, spacing: 6) {
            header
                .frame(height: headerH)

            if all.isEmpty {
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
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: WidgetLayout.rowSpacing) {
                        ForEach(pages.isEmpty ? [] : pages[page]) { r in
                            if let p = entry.pending, p.id == r.task.id.uuidString, !entry.isSample {
                                ConfirmRow(row: r, kind: p.kind, day: entry.day)
                            } else {
                                TaskRowView(row: r,
                                            day: entry.day,
                                            overdue: !entry.isSample && r.task.isOverdue(today: entry.day, nowMinutes: nowM),
                                            interactive: !entry.isSample)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if pages.count > 1 {
                        ScrollRail(familyKey: familyKey, page: page, pages: pages.count)
                            .frame(width: WidgetLayout.railW)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var header: some View {
        let doneSingles = entry.tasks.filter { $0.done }.count
        let checked = entry.longs.filter { $0.isCheckedIn(entry.day) || $0.done }.count
        let total = entry.tasks.count + entry.longs.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("今天")
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
            if total > 0 {
                ProgressRing(done: doneSingles + checked, total: total)
            }
        }
    }
}

/// One task line: check button, a time column that shows the kind of time, then the full title.
/// Long titles wrap and stay indented after the bullet.
struct TaskRowView: View {
    let row: WRow
    let day: String
    let overdue: Bool
    let interactive: Bool

    var body: some View {
        let t = row.task
        let checked = row.isLong ? t.isCheckedIn(day) : t.done
        HStack(alignment: .top, spacing: 6) {
            Group {
                if interactive {
                    Button(intent: ArmTaskIntent(taskID: t.id.uuidString, kind: row.isLong ? "checkin" : "done")) {
                        CheckDot(done: checked)
                    }
                    .buttonStyle(.plain)
                } else {
                    CheckDot(done: checked)
                }
            }
            .frame(width: WidgetLayout.checkW)

            TimeColumn(task: t, isLong: row.isLong, day: day, overdue: overdue)
                .frame(width: WidgetLayout.timeW, alignment: .leading)

            HStack(alignment: .top, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(t.color.color)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(t.color.border, lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title)
                        .font(.system(size: 13))
                        .foregroundStyle(t.done ? Palette.muted : Palette.ink)
                        .strikethrough(t.done)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.isLong {
                        CheckinTrack(task: t, today: day)
                            .frame(height: 7)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(t.done ? 0.6 : 1)
    }
}

struct TimeColumn: View {
    let task: TaskItem
    let isLong: Bool
    let day: String
    let overdue: Bool

    var body: some View {
        if isLong {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(task.dayIndex(day))/\(task.totalDays)")
                    .font(.rounded(12.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("天")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.muted)
            }
        } else {
            switch task.mode {
            case .range:
                VStack(alignment: .leading, spacing: 1) {
                    Text(DayKey.hm(task.start ?? 0))
                    Rectangle()
                        .fill(task.color.border)
                        .frame(width: 2, height: 8)
                        .padding(.leading, 4)
                    Text(DayKey.hm(task.due ?? 0))
                        .foregroundStyle(overdue ? Palette.now : Palette.ink)
                }
                .font(.rounded(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            case .start:
                VStack(alignment: .leading, spacing: 0) {
                    Text(DayKey.hm(task.start ?? 0))
                        .font(.rounded(12.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    Text("起")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                }
            case .deadline:
                VStack(alignment: .leading, spacing: 0) {
                    Text(DayKey.hm(task.due ?? 0))
                        .font(.rounded(12.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? Palette.now : Palette.ink)
                    Text(overdue ? "已过" : "前")
                        .font(.system(size: 9.5))
                        .foregroundStyle(overdue ? Palette.now : Palette.muted)
                }
            case .allDay:
                Text("全天")
                    .font(.rounded(12.5, .semibold))
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Shown after the first tap, so a stray touch never completes anything by itself.
struct ConfirmRow: View {
    let row: WRow
    let kind: String
    let day: String

    var body: some View {
        let t = row.task
        let question: String = {
            if kind == "checkin" { return t.isCheckedIn(day) ? "取消今天打卡？" : "今天打卡？" }
            return t.done ? "改回未完成？" : "确认完成？"
        }()
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(question)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(t.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Button(intent: ConfirmTaskIntent(taskID: t.id.uuidString, kind: kind)) {
                Text("确认")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.sheet)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Palette.accent))
            }
            .buttonStyle(.plain)
            Button(intent: CancelPendingIntent()) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.color.tint))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.color.border, lineWidth: 1))
    }
}

/// Right-side bar: where you are in the list, with ▲ ▼ to turn pages.
struct ScrollRail: View {
    let familyKey: String
    let page: Int
    let pages: Int

    var body: some View {
        VStack(spacing: 3) {
            Button(intent: PageWidgetIntent(family: familyKey, delta: -1, maxPage: pages - 1)) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: WidgetLayout.railW, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(page > 0 ? 1 : 0.3)

            GeometryReader { g in
                let h = g.size.height
                let thumbH = max(14, h / CGFloat(max(1, pages)))
                let y = (h - thumbH) * CGFloat(page) / CGFloat(max(1, pages - 1))
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Palette.lineStrong.opacity(0.6))
                        .frame(width: 4, height: h)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 4, height: thumbH)
                        .offset(y: y)
                }
                .frame(width: g.size.width, height: h, alignment: .top)
            }

            Button(intent: PageWidgetIntent(family: familyKey, delta: 1, maxPage: pages - 1)) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: WidgetLayout.railW, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(page < pages - 1 ? 1 : 0.3)
        }
    }
}

struct CheckDot: View {
    let done: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Palette.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.sheet)
            } else {
                Circle().stroke(Palette.ink.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .frame(width: WidgetLayout.checkW, height: 24)
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
        .description("今天要做的事和进行中的长任务。点圆圈后再点「确认」才会完成，防止误触。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
