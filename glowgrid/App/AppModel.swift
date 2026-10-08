import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

enum ViewMode: String {
    case day, month
}

struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let sub: String?
}

struct SparkBurst: Identifiable {
    let id = UUID()
    /// Point in global (screen) coordinates.
    let point: CGPoint
    let count: Int
}

struct EditorTarget: Identifiable {
    let id = UUID()
    var task: TaskItem
    var isNew: Bool
}

struct ZoomCommand: Equatable {
    let id = UUID()
    let factor: CGFloat
}

@MainActor
final class AppModel: ObservableObject {
    // Data
    @Published var tasks: [TaskItem] = []
    @Published var bg: BGSettings = BackgroundStore.load()

    // Navigation
    @Published var mode: ViewMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }
    @Published var selected: String = DayKey.today()
    @Published var month: String = DayKey.month(DayKey.today())
    /// Changes whenever the day view should scroll to "now" / the first task.
    @Published var scrollRequest = UUID()

    // Zoom
    @Published var hourHeight: CGFloat
    /// 0 means "fit the whole month on screen".
    @Published var monthRow: CGFloat
    @Published var zoomCommand: ZoomCommand?
    @Published var zoomText: String = ""

    // Overlays and sheets
    @Published var toast: ToastData?
    @Published var bursts: [SparkBurst] = []
    @Published var successTick = 0
    @Published var editor: EditorTarget?
    @Published var showSettings = false

    // Morning push
    @Published var morningEnabled: Bool {
        didSet { defaults.set(morningEnabled, forKey: "morningEnabled"); reschedule() }
    }
    @Published var morningMinute: Int {
        didSet { defaults.set(morningMinute, forKey: "morningMinute"); reschedule() }
    }
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults = UserDefaults.standard
    private var recentCheers: [String] = []
    private var toastTask: Task<Void, Never>?
    private var launched = false

    init() {
        let d = UserDefaults.standard
        mode = ViewMode(rawValue: d.string(forKey: "mode") ?? "") ?? .day
        let h = d.double(forKey: "hourHeight")
        hourHeight = h > 0 ? CGFloat(h) : 64
        monthRow = CGFloat(d.double(forKey: "monthRow"))
        morningEnabled = (d.object(forKey: "morningEnabled") as? Bool) ?? true
        morningMinute = (d.object(forKey: "morningMinute") as? Int) ?? 7 * 60
        tasks = TaskStore.load()
    }

    // MARK: - Lifecycle

    func onLaunch() async {
        guard !launched else { return }
        launched = true
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
        reschedule()
        if tasks.isEmpty {
            showToast("欢迎来到萤格～点格子就能添加第一件事", seconds: 3.6)
        }
    }

    /// Back in the foreground: pick up changes the widget made, refresh notifications.
    func becameActive() {
        tasks = TaskStore.load()
        Task { await refreshAuthorization() }
        reschedule()
    }

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = s.authorizationStatus
    }

    func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            reschedule()
        }
    }

    func reschedule() {
        NotificationScheduler.reschedule(tasks: tasks, minute: morningMinute, enabled: morningEnabled)
    }

    func sendTestPush() {
        Task {
            await refreshAuthorization()
            switch notificationStatus {
            case .authorized, .provisional, .ephemeral:
                NotificationScheduler.sendTest(tasks: tasks)
                showToast("3 秒后会收到一条早晨推送的样子～")
            case .notDetermined:
                requestNotifications()
            default:
                showToast("通知被关掉了，去设置里打开吧", seconds: 3)
                showSettings = true
            }
        }
    }

    // MARK: - Data

    /// Single-day tasks of a day.
    func dayTasks(_ day: String) -> [TaskItem] { tasks.on(day) }

    /// Long tasks running on a day.
    func longTasks(_ day: String) -> [TaskItem] { tasks.longOn(day) }

    private func commit() {
        TaskStore.save(tasks)
        WidgetCenter.shared.reloadAllTimelines()
        reschedule()
    }

    func save(_ item: TaskItem, isNew: Bool) {
        if let i = tasks.firstIndex(where: { $0.id == item.id }) {
            tasks[i] = item
        } else {
            tasks.append(item)
        }
        commit()
        if mode == .day {
            if !item.covers(selected) { selected = item.day }
            scrollRequest = UUID()
        } else {
            selected = item.day
            month = DayKey.month(item.day)
        }
        let what = item.isLong ? "\(DayKey.md(item.day))～\(DayKey.md(item.lastDay))" : item.timeLabel
        showToast(isNew ? "已添加：\(what) \(item.title)" : "已保存修改")
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        commit()
        showToast("已删除")
    }

    /// Complete / un-complete a whole task.
    func toggle(_ id: UUID, at point: CGPoint?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
        let t = tasks[i]
        commit()
        if t.done {
            cheer(for: t, at: point)
        } else {
            showToast(pick(Cheer.undo))
        }
    }

    /// Check in / out a long task for one day.
    func toggleCheckin(_ id: UUID, day: String, at point: CGPoint?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let j = tasks[i].checkins.firstIndex(of: day) {
            tasks[i].checkins.remove(at: j)
            commit()
            showToast("已取消这天的打卡")
            return
        }
        tasks[i].checkins.append(day)
        let t = tasks[i]
        commit()
        let idx = t.dayIndex(day), total = t.totalDays
        let msg = pick(Cheer.checkin)
            .replacingOccurrences(of: "{i}", with: "\(idx)")
            .replacingOccurrences(of: "{n}", with: "\(total)")
        showToast(msg, sub: "\(t.title) · 已打卡 \(t.checkins.count) / \(total) 天", seconds: 2.8)
        successTick += 1
        burst(at: point, count: 9)
    }

    // MARK: - Cheering

    private func cheer(for t: TaskItem, at point: CGPoint?) {
        let today = DayKey.today()
        if t.isLong {
            showToast("长任务「\(t.title)」整件完成！太了不起了", sub: "一共打卡 \(t.checkins.count) / \(t.totalDays) 天", seconds: 3.4)
            successTick += 1
            burst(at: point, count: 22)
            return
        }
        let list = dayTasks(t.day)
        let total = list.count
        let doneCount = list.filter { $0.done }.count
        let nowM = DayKey.nowMinutes()
        let hour = DayKey.cal.component(.hour, from: Date())
        let dWord = t.day == today ? "今天" : "这天"
        let allDone = total >= 2 && doneCount == total
        var late = t.day < today
        var early = t.day > today
        if let due = t.due, t.day == today {
            late = Double(due) < nowM
            early = Double(due) - nowM >= 60
        }

        let pool: [String]
        if allDone {
            pool = Cheer.allDone
        } else if late {
            pool = Double.random(in: 0..<1) < 0.75 ? Cheer.late : Cheer.general
        } else if early && Bool.random() {
            pool = Cheer.early
        } else if (hour >= 22 || hour < 4) && Bool.random() {
            pool = Cheer.night
        } else if (5..<9).contains(hour) && Bool.random() {
            pool = Cheer.morning
        } else {
            pool = Cheer.general
        }
        let msg = pick(pool)
            .replacingOccurrences(of: "{n}", with: "\(total)")
            .replacingOccurrences(of: "{d}", with: dWord)
        showToast(msg, sub: "\(dWord)已完成 \(doneCount) / \(total)", seconds: allDone ? 3.4 : 2.6)
        successTick += 1
        burst(at: point, count: allDone ? 22 : 9)
    }

    private func burst(at point: CGPoint?, count: Int) {
        guard let p = point else { return }
        let b = SparkBurst(point: p, count: count)
        bursts.append(b)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            self.bursts.removeAll { $0.id == b.id }
        }
    }

    private func pick(_ pool: [String]) -> String {
        let fresh = pool.filter { !recentCheers.contains($0) }
        let m = (fresh.isEmpty ? pool : fresh).randomElement() ?? "完成啦"
        recentCheers.append(m)
        if recentCheers.count > 12 { recentCheers.removeFirst() }
        return m
    }

    func showToast(_ text: String, sub: String? = nil, seconds: Double = 2.2) {
        let t = ToastData(text: text, sub: sub)
        withAnimation(.spring(duration: 0.3)) { toast = t }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            if self.toast?.id == t.id {
                withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
            }
        }
    }

    // MARK: - Backgrounds

    func saveBG() {
        BackgroundStore.save(bg)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func addBackgrounds(_ datas: [Data]) async {
        let made: [BGImage] = await Task.detached(priority: .userInitiated) {
            datas.compactMap { ImageTools.importPicture($0) }
        }.value
        guard !made.isEmpty else {
            showToast("这张图片读不出来，换一张试试吧")
            return
        }
        bg.images.append(contentsOf: made)
        saveBG()
        showToast("已添加 \(made.count) 张背景")
    }

    func deleteBackground(_ id: String) {
        bg.images.removeAll { $0.id == id }
        BackgroundStore.delete(id)
        saveBG()
    }

    func moveBackground(_ id: String, by delta: Int) {
        guard let i = bg.images.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0 && j < bg.images.count else { return }
        bg.images.swapAt(i, j)
        saveBG()
    }

    func updateCrop(_ id: String, target: BGTarget, crop: CGRect) async {
        guard let i = bg.images.firstIndex(where: { $0.id == id }) else { return }
        bg.images[i].crops[target.rawValue] = crop
        await Task.detached(priority: .userInitiated) {
            if let original = UIImage(contentsOfFile: BackgroundStore.originalURL(id).path) {
                ImageTools.writeTarget(id: id, original: original, crop: crop, target: target)
            }
        }.value
        bgVersion += 1
        saveBG()
    }

    /// Bumped when a background file is re-rendered, so views reload the picture.
    @Published var bgVersion = 0

    // MARK: - Navigation

    func select(_ day: String) {
        selected = day
        scrollRequest = UUID()
    }

    func openDay(_ day: String) {
        selected = day
        mode = .day
        scrollRequest = UUID()
    }

    func showMonth() {
        month = DayKey.month(selected)
        mode = .month
    }

    func showDay() {
        mode = .day
        scrollRequest = UUID()
    }

    func shiftMonth(_ n: Int) {
        month = DayKey.addMonths(month, n)
    }

    func goToday() {
        let t = DayKey.today()
        if mode == .month {
            selected = t
            month = DayKey.month(t)
        } else {
            select(t)
        }
    }

    func zoom(by factor: CGFloat) {
        zoomCommand = ZoomCommand(factor: factor)
    }

    func saveZoom() {
        defaults.set(Double(hourHeight), forKey: "hourHeight")
        defaults.set(Double(monthRow), forKey: "monthRow")
    }

    // MARK: - Adding

    func defaultDue(for day: String) -> Int {
        if day == DayKey.today() {
            let next = Int((DayKey.nowMinutes() / 60).rounded(.up)) * 60
            return min(max(next, 15), 23 * 60 + 45)
        }
        return 9 * 60
    }

    func newTask(day: String? = nil, due: Int? = nil) {
        var d = day ?? selected
        if day == nil && mode == .month && DayKey.month(selected) != month {
            d = month == DayKey.month(DayKey.today()) ? DayKey.today() : month + "-01"
        }
        let colors = TaskColor.allCases
        let item = TaskItem(title: "", day: d, due: due ?? defaultDue(for: d),
                            color: colors[tasks.count % colors.count])
        editor = EditorTarget(task: item, isNew: true)
    }

    func edit(_ t: TaskItem) {
        editor = EditorTarget(task: t, isNew: false)
    }

    func handle(url: URL) {
        guard url.scheme == "glowgrid" else { return }
        let today = DayKey.today()
        switch url.host ?? "" {
        case "add":
            selected = today
            mode = .day
            scrollRequest = UUID()
            newTask(day: today)
        default:
            openDay(today)
        }
    }
}
