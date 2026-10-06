import Foundation
import UserNotifications

/// Morning summaries. iOS fixes a local notification's text when it is scheduled, so every
/// time tasks change we rebuild one notification per day for the next 60 days, each carrying
/// that day's list. 60 stays under iOS's limit of 64 pending notifications.
enum NotificationScheduler {
    static let prefix = "morning-"
    static let daysAhead = 60

    static func content(for day: String, tasks: [TaskItem]) -> UNMutableNotificationContent {
        let list = tasks.on(day)
        let undone = list.filter { !$0.done }
        let c = UNMutableNotificationContent()
        if list.isEmpty {
            c.title = "早上好～今天没有安排"
            c.body = "好好休息一下吧"
        } else if undone.isEmpty {
            c.title = "早上好～今天的事都提前做完啦"
            c.body = "可以轻轻松松过一天了，真厉害"
        } else {
            c.title = "早上好～今天有 \(undone.count) 件事"
            var lines = undone.prefix(5).map { "\(DayKey.hm($0.due)) 前　\($0.title)" }
            if undone.count > 5 { lines.append("还有 \(undone.count - 5) 件…") }
            c.body = lines.joined(separator: "\n")
        }
        if let h = JPHoliday.name(day) { c.subtitle = "今天是\(h)" }
        c.sound = .default
        c.threadIdentifier = "morning"
        return c
    }

    static func reschedule(tasks: [TaskItem], minute: Int, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map { $0.identifier }.filter { $0.hasPrefix(NotificationScheduler.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard enabled else { return }
            let now = Date()
            let today = DayKey.today()
            for offset in 0..<NotificationScheduler.daysAhead {
                let day = DayKey.add(today, days: offset)
                let fire = DayKey.dateAt(day, minutes: minute)
                if fire <= now { continue }
                let comps = DayKey.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(identifier: NotificationScheduler.prefix + day,
                                                    content: NotificationScheduler.content(for: day, tasks: tasks),
                                                    trigger: trigger)
                center.add(request)
            }
        }
    }

    /// A real notification in 3 seconds with today's content, to see how it looks.
    static func sendTest(tasks: [TaskItem]) {
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                            content: content(for: DayKey.today(), tasks: tasks),
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
