import SwiftUI

/// A vertical 24-hour grid. Pinch to change how tall one hour is.
struct DayTimelineView: View {
    @EnvironmentObject var model: AppModel

    @State private var position = ScrollPosition(edge: .top)
    @State private var offsetY: CGFloat = 0
    @State private var viewportH: CGFloat = 520
    @State private var pinchStart: (h: CGFloat, anchor: CGFloat, y: CGFloat)?

    static let pad: CGFloat = 14
    static let labelW: CGFloat = 56
    static let maxH: CGFloat = 240

    private var H: CGFloat { model.hourHeight }

    private var minH: CGFloat { max(12, (viewportH - Self.pad * 2) / 24) }

    var body: some View {
        ScrollView(.vertical) {
            GeometryReader { geo in
                DayContent(width: geo.size.width, hourHeight: H)
            }
            .frame(height: H * 24 + Self.pad * 2)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, value in
            offsetY = value
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.containerSize.height
        } action: { _, value in
            guard value > 0 else { return }
            viewportH = value
            if H < minH { model.hourHeight = minH }
            updateZoomText()
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if pinchStart == nil {
                        let y = value.startLocation.y
                        pinchStart = (H, (offsetY + y - Self.pad) / H * 60, y)
                    }
                    guard let p = pinchStart else { return }
                    apply(p.h * value.magnification, anchorMinutes: p.anchor, viewportY: p.y)
                }
                .onEnded { _ in
                    pinchStart = nil
                    model.saveZoom()
                }
        )
        .onChange(of: model.zoomCommand) { _, cmd in
            guard let cmd else { return }
            let y = viewportH / 2
            apply(H * cmd.factor, anchorMinutes: (offsetY + y - Self.pad) / H * 60, viewportY: y)
            model.saveZoom()
        }
        .onChange(of: model.scrollRequest) { _, _ in focus() }
        .onAppear {
            updateZoomText()
            DispatchQueue.main.async { focus() }
        }
    }

    private func apply(_ newH: CGFloat, anchorMinutes: CGFloat, viewportY: CGFloat) {
        let h = min(Self.maxH, max(minH, newH))
        model.hourHeight = h
        position.scrollTo(y: max(0, Self.pad + anchorMinutes / 60 * h - viewportY))
        updateZoomText()
    }

    private func updateZoomText() {
        let visible = (viewportH - Self.pad * 2) / max(H, 1)
        let text: String
        if visible >= 23.5 {
            text = "一屏全天"
        } else if visible >= 3 {
            text = "一屏≈\(Int(visible.rounded()))时"
        } else {
            text = String(format: "一屏≈%.1f时", visible)
        }
        if model.zoomText != text { model.zoomText = text }
    }

    /// Scroll to "now" on today, otherwise to the first task (or 8:00).
    private func focus() {
        let minutes: Double
        var frac: CGFloat = 0.3
        if model.selected == DayKey.today() {
            minutes = DayKey.nowMinutes()
        } else {
            let list = model.dayTasks(model.selected)
            let first = list.map { $0.start ?? max(0, ($0.due ?? 8 * 60) - 60) }.min() ?? 8 * 60
            minutes = Double(first)
            frac = 0.15
        }
        let y = Self.pad + CGFloat(minutes) / 60 * H - viewportH * frac
        position.scrollTo(y: max(0, y))
    }
}

// MARK: - Content

private struct DayContent: View {
    @EnvironmentObject var model: AppModel
    let width: CGFloat
    let hourHeight: CGFloat

    var body: some View {
        let pad = DayTimelineView.pad
        let labelW = DayTimelineView.labelW
        let areaW = max(40, width - labelW - 6)
        let placed = layout(model.dayTasks(model.selected), H: hourHeight, pad: pad)
        let today = DayKey.today()
        let nowM = DayKey.nowMinutes()

        ZStack(alignment: .topLeading) {
            GridCanvas(hourHeight: hourHeight, pad: pad)
                .frame(width: width, height: hourHeight * 24 + pad * 2)
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let m = Int(((loc.y - pad) / hourHeight * 60 / 15).rounded()) * 15
                    model.newTask(day: model.selected, due: min(max(m, 15), 23 * 60 + 45))
                }

            ForEach(placed) { p in
                let colW = areaW / CGFloat(p.columns)
                let x = labelW + CGFloat(p.column) * colW + 2
                TaskBlockView(task: p.task,
                              kind: p.kind,
                              height: p.bottom - p.top,
                              compact: hourHeight < 30,
                              overdue: p.task.isOverdue(today: today, nowMinutes: nowM),
                              onToggle: { point in model.toggle(p.task.id, at: point) },
                              onEdit: { model.edit(p.task) })
                    .frame(width: max(10, colW - 4), height: p.bottom - p.top)
                    .offset(x: x, y: p.top)
                if p.kind == .flag, let due = p.task.due {
                    Rectangle()
                        .fill(p.task.color.border)
                        .frame(width: max(10, colW - 4), height: 2)
                        .offset(x: x, y: pad + CGFloat(due) / 60 * hourHeight - 1)
                        .allowsHitTesting(false)
                }
            }

            if model.selected == today {
                NowLine(hourHeight: hourHeight, pad: pad)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: hourHeight * 24 + pad * 2, alignment: .topLeading)
    }

    struct Placed: Identifiable {
        let task: TaskItem
        let kind: TaskShapeKind
        let top: CGFloat
        let bottom: CGFloat
        var column = 0
        var columns = 1
        var id: UUID { task.id }
    }

    /// Same overlap rule as the prototype: items that overlap share the width in columns.
    private func layout(_ list: [TaskItem], H: CGFloat, pad: CGFloat) -> [Placed] {
        let flagH: CGFloat = H < 30 ? 22 : 30
        var items: [Placed] = list.map { t in
            switch t.mode {
            case .range:
                let yStart = pad + CGFloat(t.start ?? 0) / 60 * H
                let yEnd = pad + CGFloat(t.due ?? 0) / 60 * H
                return Placed(task: t, kind: .block, top: yStart, bottom: max(yEnd, yStart + flagH))
            case .start:
                // Hangs below its start line with a fading tail, because the end is open.
                let yStart = pad + CGFloat(t.start ?? 0) / 60 * H
                let tail = max(flagH + 10, H * 0.9)
                return Placed(task: t, kind: .start, top: yStart, bottom: yStart + tail)
            default:
                let yDue = pad + CGFloat(t.due ?? 0) / 60 * H
                return Placed(task: t, kind: .flag, top: max(0, yDue - flagH), bottom: max(yDue, flagH))
            }
        }
        items.sort { a, b in a.top != b.top ? a.top < b.top : a.bottom < b.bottom }

        var result: [Placed] = []
        var cluster: [Placed] = []
        var clusterEnd: CGFloat = -.infinity

        func flush() {
            var ends: [CGFloat] = []
            var assigned: [Placed] = []
            for var it in cluster {
                if let c = ends.firstIndex(where: { $0 <= it.top + 0.5 }) {
                    it.column = c
                    ends[c] = it.bottom
                } else {
                    it.column = ends.count
                    ends.append(it.bottom)
                }
                assigned.append(it)
            }
            for var it in assigned {
                it.columns = max(1, ends.count)
                result.append(it)
            }
            cluster = []
        }

        for it in items {
            if !cluster.isEmpty && it.top >= clusterEnd - 0.5 {
                flush()
                clusterEnd = -.infinity
            }
            cluster.append(it)
            clusterEnd = max(clusterEnd, it.bottom)
        }
        if !cluster.isEmpty { flush() }
        return result
    }
}

// MARK: - Pieces

/// Hour lines, half / quarter lines when zoomed in, and faint vertical grid-paper lines.
struct GridCanvas: View {
    let hourHeight: CGFloat
    let pad: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 52
            var vertical = Path()
            var x: CGFloat = DayTimelineView.labelW
            while x < size.width {
                vertical.move(to: CGPoint(x: x, y: pad))
                vertical.addLine(to: CGPoint(x: x, y: size.height - pad))
                x += 22
            }
            ctx.stroke(vertical, with: .color(Palette.line.opacity(0.5)), lineWidth: 1)

            let showHalf = hourHeight >= 44
            let showQuarter = hourHeight >= 112
            let sparse = hourHeight < 24

            for i in 0...96 {
                let q = i % 4
                let hour = i / 4
                let y = (pad + CGFloat(i) / 4 * hourHeight).rounded() + 0.5
                var line = Path()
                line.move(to: CGPoint(x: left, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                if q == 0 {
                    ctx.stroke(line, with: .color(Palette.lineStrong), lineWidth: 1)
                    if !(sparse && hour % 2 == 1) {
                        let label = Text("\(hour):00")
                            .font(.rounded(12, .medium))
                            .foregroundColor(Palette.muted)
                        ctx.draw(label, at: CGPoint(x: 44, y: y), anchor: .trailing)
                    }
                } else if q == 2 {
                    guard showHalf else { continue }
                    ctx.stroke(line, with: .color(Palette.lineStrong.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    let label = Text(":30").font(.rounded(10)).foregroundColor(Palette.muted)
                    ctx.draw(label, at: CGPoint(x: 44, y: y), anchor: .trailing)
                } else {
                    guard showQuarter else { continue }
                    ctx.stroke(line, with: .color(Palette.lineStrong.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    let label = Text(":\(q * 15)").font(.rounded(10)).foregroundColor(Palette.muted)
                    ctx.draw(label, at: CGPoint(x: 44, y: y), anchor: .trailing)
                }
            }
        }
    }
}

struct NowLine: View {
    let hourHeight: CGFloat
    let pad: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let m = DayKey.nowMinutes()
            let y = pad + CGFloat(m) / 60 * hourHeight
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.now)
                    .frame(height: 2)
                    .padding(.leading, 50)
                    .offset(y: y - 1)
                Circle()
                    .fill(Palette.now)
                    .frame(width: 10, height: 10)
                    .offset(x: 46, y: y - 5)
                Text(DayKey.hm(Int(m)))
                    .font(.rounded(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.now))
                    .offset(x: 2, y: y - 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// One task in the day grid. Three looks, one per kind of time:
/// - deadline: a flag sitting on its deadline line
/// - start only: hangs below its start line and fades out (the end is open)
/// - time range: a solid block from start to end
struct TaskBlockView: View {
    let task: TaskItem
    let kind: TaskShapeKind
    let height: CGFloat
    let compact: Bool
    let overdue: Bool
    let onToggle: (CGPoint) -> Void
    let onEdit: () -> Void

    private var rowH: CGFloat { compact ? 22 : 30 }
    private var tall: Bool { kind == .block && height >= 52 }

    private var shape: UnevenRoundedRectangle {
        switch kind {
        case .flag:
            return UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 3,
                                          bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
        case .start:
            return UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 10, style: .continuous)
        case .block:
            return UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10,
                                          bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
        }
    }

    private var timeText: String {
        switch kind {
        case .flag: return "\(DayKey.hm(task.due ?? 0)) 前"
        case .start: return "\(DayKey.hm(task.start ?? 0)) 起"
        case .block: return "\(DayKey.hm(task.start ?? 0))–\(DayKey.hm(task.due ?? 0))"
        }
    }

    var body: some View {
        content
            .padding(.leading, 4)
            .padding(.trailing, compact ? 6 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: (tall || kind == .start) ? .topLeading : .leading)
            .background(fillLayer)
            .overlay(borderLayer)
            .clipShape(shape)
            .opacity(task.done ? 0.62 : 1)
            .contentShape(shape)
            .onTapGesture { onEdit() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(timeText) \(task.title)\(task.done ? "，已完成" : "")")
    }

    private var content: some View {
        HStack(alignment: tall ? .top : .center, spacing: 6) {
            CheckCircle(done: task.done, size: compact ? 13 : 17)
                .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { point in onToggle(point) }
                .accessibilityLabel(task.done ? "改回未完成" : "标记完成")
                .accessibilityAddTraits(.isButton)

            if tall {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? Palette.muted : Palette.ink)
                        .lineLimit(3)
                    Text("\(DayKey.hm(task.start ?? 0)) → \(DayKey.hm(task.due ?? 0))")
                        .font(.rounded(12, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 3)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(timeText)
                        .font(.rounded(compact ? 12 : 13, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
                    Text(task.title)
                        .font(.system(size: compact ? 12 : 14))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? Palette.muted : Palette.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if overdue {
                Text("已过")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.now)
                    .fixedSize()
            }
        }
        .frame(height: kind == .start ? rowH : nil)
        .padding(.top, tall ? 2 : 0)
    }

    @ViewBuilder
    private var fillLayer: some View {
        if kind == .start {
            ZStack(alignment: .top) {
                LinearGradient(colors: [task.color.tint, task.color.tint.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                PatternOverlay(pattern: task.pattern, color: task.color)
                    .frame(height: rowH)
                Rectangle()
                    .fill(task.color.border)
                    .frame(height: 2)
            }
        } else {
            ZStack {
                task.color.tint
                PatternOverlay(pattern: task.pattern, color: task.color)
            }
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        if kind == .start {
            shape.stroke(LinearGradient(colors: [task.color.border, task.color.border.opacity(0)],
                                        startPoint: .top, endPoint: .bottom),
                         lineWidth: 1)
        } else {
            shape.stroke(overdue ? Palette.now : task.color.border,
                         style: StrokeStyle(lineWidth: 1.2, dash: overdue ? [4, 3] : []))
        }
    }
}

/// Deadline only = flag, start only = open-ended marker, start + end = block.
enum TaskShapeKind { case flag, start, block }

struct CheckCircle: View {
    let done: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Palette.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(Palette.sheet)
            } else {
                Circle().stroke(Palette.ink.opacity(0.55), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}
