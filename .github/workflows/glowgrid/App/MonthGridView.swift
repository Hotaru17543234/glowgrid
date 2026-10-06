import SwiftUI

/// Month overview: every day is a small square with its tasks stacked as colour chips.
/// Pinching makes the rows taller, and the chips show more detail step by step.
struct MonthGridView: View {
    @EnvironmentObject var model: AppModel

    @State private var position = ScrollPosition(edge: .top)
    @State private var offsetY: CGFloat = 0
    @State private var viewport: CGSize = CGSize(width: 340, height: 500)
    @State private var pinchStart: (r: CGFloat, anchor: CGFloat, y: CGFloat)?

    static let maxRow: CGFloat = 300

    private var rows: Int { DayKey.weekRows(model.month) }
    private var fitRow: CGFloat { max(40, (viewport.height - 1) / CGFloat(rows)) }
    private var rowH: CGFloat { model.monthRow <= 0 ? fitRow : max(fitRow, model.monthRow) }

    var body: some View {
        VStack(spacing: 0) {
            WeekdayHeader()
                .frame(height: 26)
            Rectangle().fill(Palette.line).frame(height: 1)

            ScrollView(.vertical) {
                MonthGrid(month: model.month,
                          rows: rows,
                          rowH: rowH,
                          width: viewport.width)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, value in
                offsetY = value
            }
            .onScrollGeometryChange(for: CGSize.self) { geo in
                geo.containerSize
            } action: { _, value in
                guard value.width > 0, value.height > 0 else { return }
                viewport = value
                updateZoomText()
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchStart == nil {
                            let y = value.startLocation.y
                            pinchStart = (rowH, (offsetY + y) / rowH, y)
                        }
                        guard let p = pinchStart else { return }
                        apply(p.r * value.magnification, anchorRow: p.anchor, viewportY: p.y)
                    }
                    .onEnded { _ in
                        pinchStart = nil
                        model.saveZoom()
                    }
            )
            .onChange(of: model.zoomCommand) { _, cmd in
                guard let cmd else { return }
                let y = viewport.height / 2
                apply(rowH * cmd.factor, anchorRow: (offsetY + y) / rowH, viewportY: y)
                model.saveZoom()
            }
            .onChange(of: model.month) { _, _ in
                position.scrollTo(edge: .top)
                updateZoomText()
            }
            .onAppear {
                updateZoomText()
                DispatchQueue.main.async { scrollToSelected() }
            }
        }
    }

    private func apply(_ newRow: CGFloat, anchorRow: CGFloat, viewportY: CGFloat) {
        let r = min(Self.maxRow, max(fitRow, newRow))
        model.monthRow = r <= fitRow + 0.5 ? 0 : r
        position.scrollTo(y: max(0, anchorRow * r - viewportY))
        updateZoomText()
    }

    private func updateZoomText() {
        let text = MonthLayout.names[MonthLayout.level(rowH)]
        if model.zoomText != text { model.zoomText = text }
    }

    private func scrollToSelected() {
        guard DayKey.month(model.selected) == model.month else { return }
        let start = DayKey.mondayOfWeek(model.month + "-01")
        let days = DayKey.cal.dateComponents([.day], from: DayKey.date(start), to: DayKey.date(model.selected)).day ?? 0
        let row = CGFloat(max(0, days) / 7)
        position.scrollTo(y: max(0, row * rowH - rowH * 0.3))
    }
}

private struct WeekdayHeader: View {
    static let names = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(Self.names[i])
                    .font(.system(size: 11))
                    .foregroundStyle(i == 5 ? Palette.sat : i == 6 ? Palette.sun : Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.sheet)
    }
}

private struct MonthGrid: View {
    @EnvironmentObject var model: AppModel
    let month: String
    let rows: Int
    let rowH: CGFloat
    let width: CGFloat

    var body: some View {
        let start = DayKey.mondayOfWeek(month + "-01")
        let cellW = width / 7
        let level = MonthLayout.level(rowH)
        let byDay = Dictionary(grouping: model.tasks, by: { $0.day })
        let today = DayKey.today()
        let nowM = DayKey.nowMinutes()

        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let day = DayKey.add(start, days: r * 7 + c)
                        let list = (byDay[day] ?? []).on(day)
                        MonthCell(day: day,
                                  inMonth: DayKey.month(day) == month,
                                  isToday: day == today,
                                  isSelected: day == model.selected,
                                  level: level,
                                  width: cellW,
                                  height: rowH,
                                  tasks: list,
                                  today: today,
                                  nowMinutes: nowM)
                            .overlay(alignment: .trailing) {
                                if c < 6 { Rectangle().fill(Palette.line).frame(width: 1) }
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Palette.line).frame(height: 1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.openDay(day) }
                    }
                }
            }
        }
        .frame(width: width, height: rowH * CGFloat(rows), alignment: .top)
    }
}

enum MonthLayout {
    static let names = ["色条", "概览", "展开", "详细"]

    static func level(_ row: CGFloat) -> Int {
        row < 58 ? 0 : row < 140 ? 1 : row < 200 ? 2 : 3
    }

    /// Rough text width: CJK counts as 1, Latin letters and digits as about half.
    static func units(_ s: String) -> CGFloat {
        s.unicodeScalars.reduce(CGFloat(0)) { $0 + ($1.value < 0x2E80 ? 0.55 : 1) }
    }

    static func chipHeight(_ t: TaskItem, level: Int, cellW: CGFloat) -> CGFloat {
        switch level {
        case 0:
            return 4
        case 1:
            return 15
        case 2:
            let perLine = max(1, floor((cellW - 8) / 10))
            return 4 + min(2, max(1, ceil(units(t.title) / perLine))) * 12
        default:
            let perLine = max(1, floor((cellW - 10) / 11))
            return 5 + 12 + min(3, max(1, ceil(units(t.title) / perLine))) * 13
        }
    }

    /// Which chips fit in a cell; the rest become "+N".
    static func fit(_ list: [TaskItem], level: Int, cellW: CGFloat, rowH: CGFloat, holiday: Bool)
        -> (shown: [TaskItem], hidden: Int) {
        let avail = rowH - 1 - 3 - 16 - 2 - 2
        var used: CGFloat = holiday ? 13 : 0
        var shown: [TaskItem] = []
        for t in list {
            let h = chipHeight(t, level: level, cellW: cellW)
            if used + h > avail { break }
            used += h + 2
            shown.append(t)
        }
        var hidden = list.count - shown.count
        if hidden > 0 {
            while !shown.isEmpty && used + 12 > avail {
                let last = shown.removeLast()
                used -= chipHeight(last, level: level, cellW: cellW) + 2
                hidden += 1
            }
        }
        return (shown, hidden)
    }
}

private struct MonthCell: View {
    let day: String
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let level: Int
    let width: CGFloat
    let height: CGFloat
    let tasks: [TaskItem]
    let today: String
    let nowMinutes: Double

    var body: some View {
        let holiday = JPHoliday.name(day)
        let wd = DayKey.weekday(day)
        let fit = MonthLayout.fit(tasks, level: level, cellW: width, rowH: height, holiday: holiday != nil)
        let numberColor: Color = isToday ? Palette.glowInk
            : (holiday != nil || wd == 1) ? Palette.sun
            : wd == 7 ? Palette.sat : Palette.ink

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text("\(DayKey.parts(day).day)")
                    .font(.rounded(12, isToday ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isToday ? Capsule().fill(Palette.glowBG) : nil)
                Spacer(minLength: 0)
                if level >= 2 && !tasks.isEmpty {
                    Text("\(tasks.count)件")
                        .font(.rounded(9.5, .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(height: 16)

            if let h = holiday {
                Text(JPHoliday.shortName(h))
                    .font(.system(size: 8.5))
                    .foregroundStyle(Palette.sun)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 11)
                    .clipped()
            }

            ForEach(fit.shown) { t in
                MonthChip(task: t,
                          level: level,
                          height: MonthLayout.chipHeight(t, level: level, cellW: width),
                          overdue: t.isOverdue(today: today, nowMinutes: nowMinutes))
            }

            if fit.hidden > 0 {
                Text("+\(fit.hidden)")
                    .font(.rounded(9.5))
                    .foregroundStyle(Palette.muted)
                    .frame(height: 12)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .padding(.bottom, 2)
        .opacity(inMonth ? 1 : 0.42)
        .frame(width: width, height: height, alignment: .top)
        .background(inMonth ? Color.clear : Palette.paper)
        .overlay {
            if isSelected {
                Rectangle().inset(by: 1).stroke(Palette.accent, lineWidth: 2)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DayKey.md(day))\(holiday.map { "，\($0)" } ?? "")，\(tasks.count) 件事")
        .accessibilityAddTraits(.isButton)
    }
}

private struct MonthChip: View {
    let task: TaskItem
    let level: Int
    let height: CGFloat
    let overdue: Bool

    var body: some View {
        Group {
            switch level {
            case 0:
                RoundedRectangle(cornerRadius: 2)
                    .fill(overdue ? Palette.now : task.color.color)
            case 1:
                Text(task.title)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case 2:
                Text(task.title)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Text(DayKey.hm(task.due))
                        .font(.rounded(10, .semibold))
                        .monospacedDigit()
                    Text(task.title)
                        .font(.system(size: 11))
                        .lineLimit(3)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .strikethrough(task.done)
        .foregroundStyle(Palette.ink)
        .frame(height: height)
        .background(level == 0 ? nil : RoundedRectangle(cornerRadius: 4).fill(task.color.chip))
        .overlay {
            if overdue && level > 0 {
                RoundedRectangle(cornerRadius: 4).stroke(Palette.now, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: level == 0 ? 2 : 4))
        .opacity(task.done ? 0.45 : 1)
    }
}
