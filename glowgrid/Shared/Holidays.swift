import Foundation

/// Japanese national holidays under the current 祝日法 rules.
/// Checked against the Cabinet Office list for 2026 and 2027.
/// 春分・秋分 use the standard 1980–2099 formula; NAOJ fixes the official dates
/// each February for the following year, so far-future years are estimates.
enum JPHoliday {
    private static var cache: [Int: [String: String]] = [:]
    private static let lock = NSLock()

    static func name(_ k: String) -> String? {
        let y = DayKey.parts(k).year
        guard y >= 2022 && y <= 2099 else { return nil }
        return of(year: y)[k]
    }

    /// Short label for the narrow month cells.
    static func shortName(_ name: String) -> String {
        let map = ["建国記念の日": "建国記念日", "スポーツの日": "スポーツ", "勤労感謝の日": "勤労感謝"]
        return map[name] ?? name
    }

    static func of(year y: Int) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[y] { return cached }

        var h: [String: String] = [:]
        func add(_ m: Int, _ d: Int, _ n: String) {
            h[String(format: "%04d-%02d-%02d", y, m, d)] = n
        }
        func nthMonday(_ m: Int, _ n: Int) -> Int {
            let first = DayKey.date(String(format: "%04d-%02d-01", y, m))
            let dow = DayKey.cal.component(.weekday, from: first) - 1 // 0 = Sunday
            return 1 + ((8 - dow) % 7) + (n - 1) * 7
        }

        let k = Double(y - 1980)
        let q = Double((y - 1980) / 4)
        add(1, 1, "元日")
        add(1, nthMonday(1, 2), "成人の日")
        add(2, 11, "建国記念の日")
        add(2, 23, "天皇誕生日")
        add(3, Int(floor(20.8431 + 0.242194 * k - q)), "春分の日")
        add(4, 29, "昭和の日")
        add(5, 3, "憲法記念日")
        add(5, 4, "みどりの日")
        add(5, 5, "こどもの日")
        add(7, nthMonday(7, 3), "海の日")
        add(8, 11, "山の日")
        add(9, nthMonday(9, 3), "敬老の日")
        add(9, Int(floor(23.2488 + 0.242194 * k - q)), "秋分の日")
        add(10, nthMonday(10, 2), "スポーツの日")
        add(11, 3, "文化の日")
        add(11, 23, "勤労感謝の日")

        let base = Set(h.keys)
        // 国民の休日: a day sandwiched between two national holidays
        for d in base {
            let mid = DayKey.add(d, days: 1)
            if !base.contains(mid) && base.contains(DayKey.add(d, days: 2)) {
                h[mid] = "国民の休日"
            }
        }
        // 振替休日: a holiday on Sunday moves to the next day that is not a holiday
        for d in base where DayKey.weekday(d) == 1 {
            var n = DayKey.add(d, days: 1)
            while base.contains(n) { n = DayKey.add(n, days: 1) }
            if h[n] == nil { h[n] = "振替休日" }
        }

        cache[y] = h
        return h
    }
}
