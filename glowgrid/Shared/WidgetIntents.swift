import AppIntents
import Foundation

/// Small state the widget keeps between taps: which row is waiting for confirmation,
/// and which page each widget size is showing.
enum WidgetState {
    /// How long the "确认？" row stays before it cancels itself.
    static let confirmWindow: TimeInterval = 12

    struct Pending: Codable, Equatable {
        let id: String
        /// "done" or "checkin"
        let kind: String
        let at: Date
    }

    static var defaults: UserDefaults {
        if let id = AppGroup.identifier, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }

    static func pending(at date: Date = Date()) -> Pending? {
        guard let data = defaults.data(forKey: "widget.pending"),
              let p = try? JSONDecoder().decode(Pending.self, from: data) else { return nil }
        return date.timeIntervalSince(p.at) < confirmWindow ? p : nil
    }

    static func setPending(_ p: Pending?) {
        if let p, let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: "widget.pending")
        } else {
            defaults.removeObject(forKey: "widget.pending")
        }
    }

    /// Page shown by a widget size; resets every day.
    static func page(_ family: String) -> Int {
        guard defaults.string(forKey: "widget.pageDay.\(family)") == DayKey.today() else { return 0 }
        return max(0, defaults.integer(forKey: "widget.page.\(family)"))
    }

    static func setPage(_ family: String, _ page: Int) {
        defaults.set(DayKey.today(), forKey: "widget.pageDay.\(family)")
        defaults.set(max(0, page), forKey: "widget.page.\(family)")
    }
}

/// First tap on a circle: ask "确认？" instead of completing right away.
struct ArmTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "准备完成事项"

    @Parameter(title: "事项")
    var taskID: String

    @Parameter(title: "类型")
    var kind: String

    init() {}

    init(taskID: String, kind: String) {
        self.taskID = taskID
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        WidgetState.setPending(WidgetState.Pending(id: taskID, kind: kind, at: Date()))
        return .result()
    }
}

/// Second tap: really complete (or un-complete / check in).
struct ConfirmTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "确认完成事项"

    @Parameter(title: "事项")
    var taskID: String

    @Parameter(title: "类型")
    var kind: String

    init() {}

    init(taskID: String, kind: String) {
        self.taskID = taskID
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            if kind == "checkin" {
                TaskStore.toggleCheckin(id, day: DayKey.today())
            } else {
                TaskStore.toggle(id)
            }
        }
        WidgetState.setPending(nil)
        return .result()
    }
}

struct CancelPendingIntent: AppIntent {
    static var title: LocalizedStringResource = "取消"

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetState.setPending(nil)
        return .result()
    }
}

/// ▲ / ▼ on the widget's scroll bar.
struct PageWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "翻页"

    @Parameter(title: "尺寸")
    var family: String

    @Parameter(title: "方向")
    var delta: Int

    @Parameter(title: "最后一页")
    var maxPage: Int

    init() {}

    init(family: String, delta: Int, maxPage: Int) {
        self.family = family
        self.delta = delta
        self.maxPage = maxPage
    }

    func perform() async throws -> some IntentResult {
        let next = min(max(0, maxPage), max(0, WidgetState.page(family) + delta))
        WidgetState.setPage(family, next)
        return .result()
    }
}
