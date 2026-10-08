import SwiftUI

/// A thin track for the whole span: filled up to today, with a dot for every day checked in.
struct CheckinTrack: View {
    let task: TaskItem
    let today: String

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, task.totalDays)
            let w = size.width, h = size.height
            let y = h / 2 - 2
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: w, height: 4), cornerRadius: 2),
                     with: .color(Palette.lineStrong.opacity(0.6)))
            let idx = min(n, max(0, task.dayIndex(today)))
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: w * CGFloat(idx) / CGFloat(n), height: 4), cornerRadius: 2),
                     with: .color(task.color.color.opacity(0.7)))
            let step = w / CGFloat(n)
            let r = min(3.5, max(1.5, step * 0.32))
            for d in task.checkins {
                let i = task.dayIndex(d) - 1
                guard i >= 0 && i < n else { continue }
                let cx = step * (CGFloat(i) + 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: h / 2 - r, width: 2 * r, height: 2 * r)),
                         with: .color(task.color.border))
            }
        }
    }
}
