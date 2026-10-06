import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget

    @State private var title: String
    @State private var date: Date
    @State private var due: Date
    @State private var hasStart: Bool
    @State private var start: Date
    @State private var color: TaskColor
    @State private var note: String
    @State private var errorText = ""
    @State private var deleteArmed = false
    @FocusState private var titleFocused: Bool

    init(target: EditorTarget) {
        self.target = target
        let t = target.task
        _title = State(initialValue: t.title)
        _date = State(initialValue: DayKey.date(t.day))
        _due = State(initialValue: DayKey.dateAt(t.day, minutes: t.due))
        _hasStart = State(initialValue: t.start != nil)
        _start = State(initialValue: DayKey.dateAt(t.day, minutes: t.start ?? max(0, t.due - 60)))
        _color = State(initialValue: t.color)
        _note = State(initialValue: t.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("比如：交实验报告", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                } header: {
                    Text("要做什么")
                }

                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    DatePicker("几点之前", selection: $due, displayedComponents: .hourAndMinute)
                    Toggle(isOn: $hasStart.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("设置开始时间")
                            Text("填了会画成一段色块，不填就是截止小旗")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    if hasStart {
                        DatePicker("几点开始", selection: $start, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    HStack(spacing: 0) {
                        ForEach(TaskColor.allCases) { c in
                            Button {
                                color = c
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(c.color)
                                        .frame(width: 30, height: 30)
                                        .padding(3)
                                        .overlay(Circle().stroke(color == c ? Palette.ink : Color.clear, lineWidth: 2))
                                    Text(c.label)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.muted)
                                }
                                .frame(maxWidth: .infinity)
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
                    TextField("想补充的话", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("备注（选填）")
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
            .onAppear {
                if target.isNew { titleFocused = true }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorText = "写一下要做什么吧"
            return
        }
        let dueMinutes = DayKey.minutes(of: due)
        let startMinutes: Int? = hasStart ? DayKey.minutes(of: start) : nil
        if let s = startMinutes, s >= dueMinutes {
            errorText = "开始时间要比截止时间早哦"
            return
        }
        var item = target.task
        item.title = cleanTitle
        item.day = DayKey.key(date)
        item.due = dueMinutes
        item.start = startMinutes
        item.color = color
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
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
