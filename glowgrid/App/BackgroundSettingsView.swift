import PhotosUI
import SwiftUI
import UIKit

struct BackgroundSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $picks, maxSelectionCount: 20, matching: .images) {
                    Label(importing ? "正在导入…" : "从相册添加图片", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(importing)

                ForEach(Array(model.bg.images.enumerated()), id: \.element.id) { pair in
                    NavigationLink {
                        CropScreen(imageID: pair.element.id)
                            .environmentObject(model)
                    } label: {
                        HStack(spacing: 12) {
                            BGThumb(id: pair.element.id, version: model.bgVersion)
                                .frame(width: 64, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(pair.offset + 1) 张")
                                Text("点这里裁切")
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.bg.images[$0].id }
                    for id in ids { model.deleteBackground(id) }
                }
                .onMove { from, to in
                    model.bg.images.move(fromOffsets: from, toOffset: to)
                    model.saveBG()
                }
            } header: {
                Text("图片")
            } footer: {
                Text("点一张图，可以分别裁切 App、中号、大号小组件要显示的部分。左滑可以删除，点右上角「编辑」可以调整顺序。")
            }

            Section {
                Toggle("在 App 里显示", isOn: binding(\.appEnabled))
                Toggle("在小组件里显示", isOn: binding(\.widgetEnabled))
                Toggle("随机顺序", isOn: binding(\.shuffle))
            } header: {
                Text("在哪里显示")
            }

            Section {
                Picker("App 里多久换一张", selection: binding(\.appInterval)) {
                    Text("10 秒").tag(10.0)
                    Text("30 秒").tag(30.0)
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                    Text("不换").tag(0.0)
                }
                Picker("小组件多久换一张", selection: binding(\.widgetInterval)) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("3 小时").tag(180)
                    Text("每天").tag(1440)
                }
                Picker("切换效果", selection: binding(\.effect)) {
                    ForEach(BGEffect.allCases) { e in
                        Text(e.label).tag(e)
                    }
                }
            } header: {
                Text("轮换")
            } footer: {
                Text("小组件按苹果的时间表刷新，最快 15 分钟换一张，切换动画最长 2 秒；「模糊溶解」和「缓慢推镜」在小组件里会用淡入淡出代替。")
            }

            Section {
                Slider(value: binding(\.dim), in: 0.2...0.85) {
                    Text("遮罩浓度")
                } minimumValueLabel: {
                    Text("图").font(.caption2)
                } maximumValueLabel: {
                    Text("字").font(.caption2)
                }
                DimPreview(imageID: model.bg.images.first?.id, dim: model.bg.dim, version: model.bgVersion)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } header: {
                Text("遮罩浓度")
            } footer: {
                Text("在图片上盖一层淡淡的纸色：往「字」那边拉，文字更清楚；往「图」那边拉，图片更鲜艳。")
            }
        }
        .navigationTitle("背景图片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.bg.images.isEmpty { EditButton() }
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            importing = true
            Task {
                var datas: [Data] = []
                for item in items {
                    if let d = try? await item.loadTransferable(type: Data.self) { datas.append(d) }
                }
                await model.addBackgrounds(datas)
                picks = []
                importing = false
                if model.bg.images.count == datas.count && !model.bg.appEnabled && !model.bg.widgetEnabled {
                    model.bg.appEnabled = true
                    model.bg.widgetEnabled = true
                    model.saveBG()
                }
            }
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<BGSettings, T>) -> Binding<T> {
        Binding(
            get: { model.bg[keyPath: kp] },
            set: { model.bg[keyPath: kp] = $0; model.saveBG() }
        )
    }
}

struct BGThumb: View {
    let id: String
    let version: Int

    var body: some View {
        if let ui = BGPicture.load(id, .medium, version: version) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
        } else {
            Palette.line
        }
    }
}

/// How text reads on the picture with the current mask.
struct DimPreview: View {
    let imageID: String?
    let dim: Double
    let version: Int

    var body: some View {
        ZStack(alignment: .leading) {
            if let id = imageID, let ui = BGPicture.load(id, .medium, version: version) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Palette.lineStrong
            }
            Palette.paper.opacity(dim)
            VStack(alignment: .leading, spacing: 4) {
                Text("今天 · 3 件事")
                    .font(.rounded(15, .bold))
                Text("12:00 前　取快递")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
        }
    }
}

/// Crop one picture for each place it appears.
struct CropScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let imageID: String

    @State private var target: BGTarget = .app
    @State private var original: UIImage?
    @State private var edits: [BGTarget: CGRect] = [:]
    @State private var resetCount = 0
    @State private var saving = false

    private func stored(_ t: BGTarget) -> CGRect {
        if let c = edits[t] { return c }
        if let c = model.bg.images.first(where: { $0.id == imageID })?.crop(t) { return c }
        if let img = original { return ImageTools.centeredCrop(imageSize: img.size, aspect: t.aspect) }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("裁切给", selection: $target) {
                ForEach(BGTarget.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if let img = original {
                CropEditor(image: img, aspect: target.aspect, initial: stored(target)) { rect in
                    edits[target] = rect
                }
                .id("\(target.rawValue)-\(resetCount)")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text("拖动可以移动，双指可以缩放，框里的部分就是会显示出来的样子。")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button("恢复居中") {
                    if let img = original {
                        edits[target] = ImageTools.centeredCrop(imageSize: img.size, aspect: target.aspect)
                        resetCount += 1
                    }
                }
                .buttonStyle(.bordered)

                Button(saving ? "保存中…" : "保存裁切") {
                    saving = true
                    Task {
                        for (t, rect) in edits {
                            await model.updateCrop(imageID, target: t, crop: rect)
                        }
                        saving = false
                        model.showToast("裁切已保存")
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || edits.isEmpty)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .navigationTitle("裁切")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if original == nil {
                original = UIImage(contentsOfFile: BackgroundStore.originalURL(imageID).path)
            }
        }
    }
}

/// Drag and pinch a picture behind a fixed-ratio frame. Reports the visible part as a normalised rect.
struct CropEditor: View {
    let image: UIImage
    let aspect: CGFloat
    let initial: CGRect
    let onChange: (CGRect) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var zoomStart: CGFloat?
    @State private var offsetStart: CGSize?
    @State private var configured = false

    var body: some View {
        GeometryReader { geo in
            let frame = frameSize(in: geo.size)
            let base = max(frame.width / max(1, image.size.width), frame.height / max(1, image.size.height))
            let disp = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)

            ZStack {
                Color.black.opacity(0.9)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: disp.width, height: disp.height)
                    .offset(offset)
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRect(CGRect(x: (geo.size.width - frame.width) / 2,
                                     y: (geo.size.height - frame.height) / 2,
                                     width: frame.width, height: frame.height))
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if offsetStart == nil { offsetStart = offset }
                        let s = offsetStart ?? .zero
                        offset = clamp(CGSize(width: s.width + v.translation.width,
                                              height: s.height + v.translation.height),
                                       disp: disp, frame: frame)
                    }
                    .onEnded { _ in
                        offsetStart = nil
                        report(disp: disp, frame: frame)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if zoomStart == nil { zoomStart = zoom }
                        zoom = min(6, max(1, (zoomStart ?? 1) * v.magnification))
                        let newDisp = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                        offset = clamp(offset, disp: newDisp, frame: frame)
                    }
                    .onEnded { _ in
                        zoomStart = nil
                        let newDisp = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                        report(disp: newDisp, frame: frame)
                    }
            )
            .onAppear {
                guard !configured else { return }
                configured = true
                configure(frame: frame, base: base)
            }
        }
    }

    private func frameSize(in size: CGSize) -> CGSize {
        let maxW = max(40, size.width - 48)
        let maxH = max(40, size.height - 48)
        var w = maxW
        var h = w / aspect
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        return CGSize(width: w, height: h)
    }

    private func clamp(_ o: CGSize, disp: CGSize, frame: CGSize) -> CGSize {
        let mx = max(0, (disp.width - frame.width) / 2)
        let my = max(0, (disp.height - frame.height) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }

    private func configure(frame: CGSize, base: CGFloat) {
        let c = initial
        guard c.width > 0, c.height > 0 else { return }
        zoom = min(6, max(1, frame.width / max(1, image.size.width * base * c.width)))
        let disp = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
        let ox = disp.width / 2 - frame.width / 2 - c.minX * disp.width
        let oy = disp.height / 2 - frame.height / 2 - c.minY * disp.height
        offset = clamp(CGSize(width: ox, height: oy), disp: disp, frame: frame)
    }

    private func report(disp: CGSize, frame: CGSize) {
        guard disp.width > 0, disp.height > 0 else { return }
        let left = (disp.width / 2 - frame.width / 2 - offset.width) / disp.width
        let top = (disp.height / 2 - frame.height / 2 - offset.height) / disp.height
        let rect = CGRect(x: max(0, left), y: max(0, top),
                          width: min(1, frame.width / disp.width), height: min(1, frame.height / disp.height))
        onChange(rect)
    }
}
