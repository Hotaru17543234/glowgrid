import Foundation

/// Small date helpers built around "yyyy-MM-dd" day keys, so days compare as plain strings.
enum DayKey {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = 2 // Monday
        return c
    }()

    static let weekdayCN = ["日", "一", "二", "三", "四", "五", "六"]

    static func key(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func parts(_ k: String) -> (year: Int, month: Int, day: Int) {
        let p = k.split(separator: "-").compactMap { Int($0) }
        return (p.count > 0 ? p[0] : 2000, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    static func date(_ k: String) -> Date {
        let p = parts(k)
        return cal.date(from: DateComponents(year: p.year, month: p.month, day: p.day)) ?? Date()
    }

    static func add(_ k: String, days: Int) -> String {
        let base = date(k)
        return key(cal.date(byAdding: .day, value: days, to: base) ?? base)
    }

    static func today() -> String { key(Date()) }

    /// 1 = Sunday ... 7 = Saturday
    static func weekday(_ k: String) -> Int { cal.component(.weekday, from: date(k)) }

    static func weekdayName(_ k: String) -> String { weekdayCN[weekday(k) - 1] }

    /// "yyyy-MM"
    static func month(_ k: String) -> String { String(k.prefix(7)) }

    static func addMonths(_ monthKey: String, _ n: Int) -> String {
        let p = parts(monthKey + "-01")
        let d = cal.date(from: DateComponents(year: p.year, month: p.month + n, day: 1)) ?? Date()
        return month(key(d))
    }

    static func mondayOfWeek(_ k: String) -> String {
        let offset = (weekday(k) + 5) % 7
        return add(k, days: -offset)
    }

    /// Number of week rows a month needs in a Monday-first grid.
    static func weekRows(_ monthKey: String) -> Int {
        let first = monthKey + "-01"
        let lead = (weekday(first) + 5) % 7
        let days = cal.range(of: .day, in: .month, for: date(first))?.count ?? 30
        return Int(ceil(Double(lead + days) / 7.0))
    }

    static func nowMinutes() -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: Date())
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60.0
    }

    /// 570 -> "9:30"
    static func hm(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "10月6日"
    static func md(_ k: String) -> String {
        let p = parts(k)
        return "\(p.month)月\(p.day)日"
    }

    static func dateAt(_ k: String, minutes: Int) -> Date {
        let base = date(k)
        return cal.date(byAdding: .minute, value: minutes, to: base) ?? base
    }

    static func minutes(of d: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
