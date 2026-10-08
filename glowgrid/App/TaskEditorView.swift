import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget

    @State private var title: String
    @State private var date: Date
    @State private var isLong: Bool
    @State private var endDate: Date
    @State private var mode: TimeMode
    @State private var start: Date
    @State private var due: Date
    @State private var color: TaskColor
    @State private var pattern: TaskPattern
    @State private var note: String
    @State private var done: Bool
    @State private var errorText = ""
    @State private var deleteArmed = false
    @FocusState private var titleFocused: Bool

    init(target: EditorTarget) {
        self.target = target
        let t = target.task
        _title = State(initialValue: t.title)
        _date = State(initialValue: DayKey.date(t.day))
        _isLong = State(initialValue: t.isLong)
        _endDate = State(initialValue: DayKey.date(t.isLong ? t.lastDay : DayKey.add(t.day, days: 6)))
        var m = t.mode
        if m == .allDay && !t.isLong { m = .deadline }
        _mode = State(initialValue: m)
        let dueMin = t.due ?? ((t.start ?? 9 * 60) + 60)
        let startMin = t.start ?? max(0, dueMin - 60)
        _start = State(initialValue: DayKey.dateAt(t.day, minutes: startMin))
        _due = State(initialValue: DayKey.dateAt(t.day, minutes: min(dueMin, 23 * 60 + 59)))
        _color = State(initialValue: t.color)
        _pattern = State(initialValue: t.pattern)
        _note = State(initialValue: t.note)
        _done = State(initialValue: t.done)
    }

    private var modes: [TimeMode] {
        isLong ? [.deadline, .start, .range, .allDay] : [.deadline, .start, .range]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("比如：交实验报告", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($titleFocused)
                } header: {
                    Text("要做什么")
                }

                Section {
                    DatePicker(isLong ? "开始日期" : "日期", selection: $date, displayedComponents: .date)
                    Toggle(isOn: $isLong.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("跨好几天的长任务")
                            Text("在月历里画成横条，每天都可以打卡")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    if isLong {
                        DatePicker("结束日期", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                } header: {
                    Text("哪一天")
                }

                Section {
                    Picker("时间方式", selection: $mode) {
                        ForEach(modes) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .deadline:
                        DatePicker(isLong ? "最后一天几点前" : "几点之前", selection: $due, displayedComponents: .hourAndMinute)
                    case .start:
                        DatePicker(isLong ? "第一天几点开始" : "几点开始", selection: $start, displayedComponents: .hourAndMinute)
                    case .range:
                        DatePicker(isLong ? "第一天几点开始" : "开始", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker(isLong ? "最后一天几点结束" : "结束", selection: $due, displayedComponents: .hourAndMinute)
                    case .allDay:
                        Text("不定具体时间，只看日期")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                } header: {
                    Text("时间")
                } footer: {
                    Text(modeHint)
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                        ForEach(TaskColor.allCases) { c in
                            Button {
                                color = c
                            } label: {
                                VStack(spacing: 3) {
                                    Circle()
                                        .fill(c.color)
                                        .overlay(Circle().stroke(c.border, lineWidth: 1.5))
                                        .frame(width: 28, height: 28)
                                        .padding(3)
                                        .overlay(Circle().stroke(color == c ? Palette.ink : Color.clear, lineWidth: 2))
                                    Text(c.label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.label)
                            .accessibilityAddTraits(color == c ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("颜色")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(TaskPattern.allCases) { p in
                            Button {
                                pattern = p
                            } label: {
                                HStack(spacing: 4) {
                                    Text(p.label)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(
                                    ZStack {
                                        color.tint
                                        PatternOverlay(pattern: p, color: color)
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(pattern == p ? Palette.ink : color.border, lineWidth: pattern == p ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.label)
                            .accessibilityAddTraits(pattern == p ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("标签样式")
                } footer: {
                    Text("花纹只画在标签右边，文字那一侧保持干净，不影响阅读。")
                }

                Section {
                    TextField("想补充的话", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("备注（选填）")
                }

                if !target.isNew {
                    Section {
                        Toggle(isLong ? "整件事已经完成" : "已完成", isOn: $done)
                    }
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText).foregroundStyle(Palette.now)
                    }
                }

                if !target.isNew {
                    Section {
                        Button(role: .destructive) {
                            deleteTapped()
                        } label: {
                            Text(deleteArmed ? "再点一次删除" : "删除这件事")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(target.isNew ? "添加事项" : "编辑事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: isLong) { _, long in
                if !long && mode == .allDay { mode = .deadline }
            }
            .onChange(of: date) { _, newStart in
                // Keep the end date after the start date.
                if DayKey.key(endDate) <= DayKey.key(newStart) {
                    endDate = DayKey.date(DayKey.add(DayKey.key(newStart), days: 1))
                }
            }
            .onAppear {
                if target.isNew { titleFocused = true }
            }
        }
        .presentationDetents([.large])
    }

    private var modeHint: String {
        switch mode {
        case .deadline: return "只定一个截止时间，时间格里画成插在截止线上的小旗。"
        case .start: return "只定开始时间、不知道什么时候结束，画成从开始线往下慢慢变淡的标签。"
        case .range: return "开始和结束都定好，画成一整段色块。"
        case .allDay: return "只看日期，在长任务横条和顶部进度里显示。"
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorText = "写一下要做什么吧"
            return
        }
        let dayKey = DayKey.key(date)
        let endKey = DayKey.key(endDate)
        if isLong && endKey <= dayKey {
            errorText = "结束日期要比开始日期晚哦"
            return
        }
        var startMinutes: Int? = nil
        var dueMinutes: Int? = nil
        switch mode {
        case .deadline: dueMinutes = DayKey.minutes(of: due)
        case .start: startMinutes = DayKey.minutes(of: start)
        case .range:
            startMinutes = DayKey.minutes(of: start)
            dueMinutes = DayKey.minutes(of: due)
        case .allDay: break
        }
        if !isLong, let s = startMinutes, let d = dueMinutes, s >= d {
            errorText = "开始时间要比结束时间早哦"
            return
        }
        var item = target.task
        item.title = cleanTitle
        item.day = dayKey
        item.endDay = isLong ? endKey : nil
        item.start = startMinutes
        item.due = dueMinutes
        item.color = color
        item.pattern = pattern
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.done = done
        if !isLong { item.checkins = [] }
        model.save(item, isNew: target.isNew)
        dismiss()
    }

    private func deleteTapped() {
        if !deleteArmed {
            deleteArmed = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                deleteArmed = false
            }
            return
        }
        model.delete(target.task.id)
        dismiss()
    }
}
