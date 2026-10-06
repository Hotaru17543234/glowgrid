import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()
                    .padding(.horizontal, 16)

                Group {
                    if model.mode == .day {
                        DayTimelineView()
                    } else {
                        MonthGridView()
                    }
                }
                .background(Palette.sheet)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
                .padding(.horizontal, 16)

                BottomBar()
                    .padding(.horizontal, 16)
            }

            ToastView()
                .allowsHitTesting(false)

            SparkLayer()
                .allowsHitTesting(false)
        }
        .tint(Palette.accent)
        .sensoryFeedback(.success, trigger: model.successTick)
        .sheet(item: $model.editor) { target in
            TaskEditorView(target: target)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
        }
        .task { await model.onLaunch() }
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("萤格").font(.rounded(15, .bold)).foregroundStyle(Palette.ink)
                    Text("GLOWGRID").font(.rounded(10, .semibold)).tracking(1.6).foregroundStyle(Palette.muted)
                }
                Spacer()
                ModeSwitch()
            }

            if model.mode == .day {
                dayTitle
                daySummary
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                WeekStrip()
            } else {
                monthTitle
                monthSummary
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var relativeWord: String {
        let today = DayKey.today()
        switch model.selected {
        case today: return " · 今天"
        case DayKey.add(today, days: 1): return " · 明天"
        case DayKey.add(today, days: -1): return " · 昨天"
        default: return ""
        }
    }

    private var dayTitle: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(DayKey.md(model.selected))
                .font(.rounded(30, .semibold))
                .foregroundStyle(Palette.ink)
            Text("周" + DayKey.weekdayName(model.selected) + relativeWord)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.selected != DayKey.today() {
                PillButton(title: "回到今天") { model.goToday() }
            }
        }
    }

    private var daySummary: Text {
        let list = model.dayTasks(model.selected)
        var t = Text("")
        if let h = JPHoliday.name(model.selected) {
            t = t + Text(h).foregroundColor(Palette.sun).fontWeight(.semibold) + Text(" · ")
        }
        if list.isEmpty {
            return t + Text("这天还没有事项 · 点格子或右下角 + 就能添加")
        }
        let done = list.filter { $0.done }.count
        t = t + Text("\(list.count)").foregroundColor(Palette.ink).fontWeight(.semibold)
            + Text(" 件事 · 已完成 ")
            + Text("\(done)").foregroundColor(Palette.ink).fontWeight(.semibold)
        if model.selected == DayKey.today() {
            let nowM = DayKey.nowMinutes()
            if let next = list.first(where: { !$0.done && Double($0.due) > nowM }) {
                t = t + Text(" · 下一件 ")
                    + Text("\(DayKey.hm(next.due)) 前").foregroundColor(Palette.ink).fontWeight(.semibold)
                    + Text(" " + next.title)
            }
        }
        return t
    }

    private var monthTitle: some View {
        let p = DayKey.parts(model.month + "-01")
        return HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(p.month)月")
                .font(.rounded(30, .semibold))
                .foregroundStyle(Palette.ink)
            Text(String(p.year) + "年")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
            if model.month != DayKey.month(DayKey.today()) {
                PillButton(title: "回到本月") { model.goToday() }
            }
            HStack(spacing: 4) {
                SquareIconButton(systemName: "chevron.left", label: "上个月") { model.shiftMonth(-1) }
                SquareIconButton(systemName: "chevron.right", label: "下个月") { model.shiftMonth(1) }
            }
        }
    }

    private var monthSummary: Text {
        let list = model.tasks.filter { DayKey.month($0.day) == model.month }
        if list.isEmpty { return Text("这个月还没有事项") }
        let done = list.filter { $0.done }.count
        let today = DayKey.today()
        let nowM = DayKey.nowMinutes()
        let overdue = list.filter { $0.isOverdue(today: today, nowMinutes: nowM) }.count
        var t = Text("本月 ")
            + Text("\(list.count)").foregroundColor(Palette.ink).fontWeight(.semibold)
            + Text(" 件事 · 已完成 ")
            + Text("\(done)").foregroundColor(Palette.ink).fontWeight(.semibold)
        if overdue > 0 {
            t = t + Text(" · 过期未完成 ") + Text("\(overdue)").foregroundColor(Palette.now).fontWeight(.semibold)
        }
        return t
    }
}

struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().stroke(Palette.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SquareIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 40, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.sheet))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ModeSwitch: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            segment("日", active: model.mode == .day) { model.showDay() }
            segment("月", active: model.mode == .month) { model.showMonth() }
        }
        .padding(3)
        .background(Capsule().fill(Palette.sheet))
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if !active { withAnimation(.easeOut(duration: 0.2)) { action() } }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Palette.paper : Palette.muted)
                .frame(minWidth: 46, minHeight: 30)
                .background(active ? Capsule().fill(Palette.ink) : nil)
        }
        .buttonStyle(.plain)
    }
}

struct WeekStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let monday = DayKey.mondayOfWeek(model.selected)
        let today = DayKey.today()
        HStack(spacing: 2) {
            Button { model.select(DayKey.add(model.selected, days: -7)) } label: {
                Image(systemName: "chevron.left").frame(width: 26, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("上一周")

            ForEach(0..<7, id: \.self) { i in
                let d = DayKey.add(monday, days: i)
                DayChip(day: d,
                        isSelected: d == model.selected,
                        isToday: d == today,
                        hasTasks: model.tasks.contains { $0.day == d })
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(d) }
            }

            Button { model.select(DayKey.add(model.selected, days: 7)) } label: {
                Image(systemName: "chevron.right").frame(width: 26, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("下一周")
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > 50 && abs(dx) > abs(dy) * 1.5 {
                    model.select(DayKey.add(model.selected, days: dx < 0 ? 7 : -7))
                }
            }
        )
    }
}

struct DayChip: View {
    let day: String
    let isSelected: Bool
    let isToday: Bool
    let hasTasks: Bool

    var body: some View {
        let wd = DayKey.weekday(day)
        let holiday = JPHoliday.name(day) != nil
        let labelColor: Color = isSelected ? Palette.paper
            : (holiday || wd == 1) ? Palette.sun
            : wd == 7 ? Palette.sat : Palette.muted
        let numberColor: Color = isSelected ? Palette.paper
            : isToday ? Palette.glowInk
            : holiday ? Palette.sun : Palette.ink

        VStack(spacing: 2) {
            Text(DayKey.weekdayName(day))
                .font(.system(size: 11))
                .foregroundStyle(labelColor)
            Text("\(DayKey.parts(day).day)")
                .font(.rounded(17, .medium))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .padding(.horizontal, 6)
                .background(isToday && !isSelected ? Capsule().fill(Palette.glowBG) : nil)
            Circle()
                .fill(isSelected ? Palette.glowBG : Palette.muted)
                .frame(width: 4, height: 4)
                .opacity(hasTasks ? 0.85 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(isSelected ? RoundedRectangle(cornerRadius: 12).fill(Palette.ink) : nil)
    }
}

// MARK: - Bottom bar

struct BottomBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button { model.zoom(by: 1 / 1.3) } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36)
                }
                .accessibilityLabel("缩小")
                Text(model.zoomText)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .frame(minWidth: 62)
                Button { model.zoom(by: 1.3) } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
                .accessibilityLabel("放大")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink)
            .padding(3)
            .background(Capsule().fill(Palette.sheet))
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))

            Button { model.sendTestPush() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell")
                    Text("推送").font(.system(size: 13))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Capsule().fill(Palette.sheet))
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发一条早晨推送试试")

            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.sheet))
                    .overlay(Circle().stroke(Palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")

            Spacer(minLength: 0)

            Button { model.newTask() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.paper)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.ink))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加事项")
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Toast and sparks

struct ToastView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack {
            Spacer()
            if let t = model.toast {
                VStack(spacing: 2) {
                    Text(t.text)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                    if let sub = t.sub {
                        Text(sub)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                }
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.ink))
                .padding(.horizontal, 24)
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SparkLayer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack {
                if !reduceMotion {
                    ForEach(model.bursts) { b in
                        SparkBurstView(count: b.count)
                            .position(x: b.point.x - origin.x, y: b.point.y - origin.y)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// A handful of firefly dots drifting up and fading out.
struct SparkBurstView: View {
    struct Particle: Identifiable {
        let id: Int
        let dx: CGFloat
        let dy: CGFloat
        let scale: CGFloat
        let duration: Double
        let delay: Double
    }

    let count: Int
    @State private var particles: [Particle] = []
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(Palette.spark)
                    .frame(width: 8, height: 8)
                    .shadow(color: Palette.spark, radius: 6)
                    .scaleEffect(go ? p.scale * 0.4 : p.scale)
                    .offset(x: go ? p.dx : 0, y: go ? p.dy : 0)
                    .opacity(go ? 0 : 1)
                    .animation(.easeOut(duration: p.duration).delay(p.delay), value: go)
            }
        }
        .frame(width: 1, height: 1)
        .onAppear {
            let big = count > 12
            particles = (0..<count).map { i in
                Particle(id: i,
                         dx: CGFloat.random(in: -0.5...0.5) * (big ? 170 : 90),
                         dy: -(30 + CGFloat.random(in: 0...1) * (big ? 140 : 75)),
                         scale: CGFloat.random(in: 0.6...1.4),
                         duration: Double.random(in: 0.8...1.4),
                         delay: Double.random(in: 0...0.12))
            }
            DispatchQueue.main.async { go = true }
        }
    }
}
