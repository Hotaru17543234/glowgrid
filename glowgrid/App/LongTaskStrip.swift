import SwiftUI

/// Long tasks running on the selected day, shown above the time grid.
/// The circle checks in for this day; tapping the row opens the editor.
struct LongTaskStrip: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded = false

    var body: some View {
        let day = model.selected
        let list = model.longTasks(day)
        if !list.isEmpty {
            VStack(spacing: 6) {
                ForEach(expanded ? list : Array(list.prefix(2))) { t in
                    LongTaskRow(task: t,
                                day: day,
                                onCheck: { p in model.toggleCheckin(t.id, day: day, at: p) },
                                onEdit: { model.edit(t) })
                }
                if list.count > 2 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "收起" : "还有 \(list.count - 2) 件长任务")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LongTaskRow: View {
    let task: TaskItem
    let day: String
    let onCheck: (CGPoint) -> Void
    let onEdit: () -> Void

    var body: some View {
        let checked = task.isCheckedIn(day)
        HStack(spacing: 10) {
            CheckCircle(done: checked, size: 20)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { p in onCheck(p) }
                .accessibilityLabel(checked ? "取消今天的打卡" : "今天打卡")
                .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(task.done ? Palette.muted : Palette.ink)
                        .strikethrough(task.done)
                        .lineLimit(1)
                    if task.done {
                        Text("已完成")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    Spacer(minLength: 0)
                    Text(task.longLabel(on: day))
                        .font(.rounded(11, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                CheckinTrack(task: task, today: day)
                    .frame(height: 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                task.color.tint
                PatternOverlay(pattern: task.pattern, color: task.color)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(task.color.border, lineWidth: 1.2))
        .opacity(task.done ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}
