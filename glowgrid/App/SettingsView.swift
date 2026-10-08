import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var morningTime: Binding<Date> {
        Binding(
            get: { DayKey.dateAt(DayKey.today(), minutes: model.morningMinute) },
            set: { model.morningMinute = DayKey.minutes(of: $0) }
        )
    }

    private var statusText: String {
        switch model.notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "已关闭"
        default: return "还没决定"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("每天早上推送今日事项", isOn: $model.morningEnabled)
                    if model.morningEnabled {
                        DatePicker("推送时间", selection: morningTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("早晨推送")
                } footer: {
                    Text("会提前排好未来 60 天的早晨推送。每次打开萤格或修改事项，都会自动更新推送里的清单。")
                }

                Section {
                    LabeledContent("通知权限", value: statusText)
                    if model.notificationStatus == .denied {
                        Button("去系统设置打开通知") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else if model.notificationStatus == .notDetermined {
                        Button("允许通知") { model.requestNotifications() }
                    }
                    Button("发一条测试推送（3 秒后）") {
                        model.sendTestPush()
                    }
                } header: {
                    Text("通知")
                }

                Section {
                    NavigationLink {
                        BackgroundSettingsView()
                            .environmentObject(model)
                    } label: {
                        LabeledContent("背景图片", value: model.bg.images.isEmpty ? "未设置" : "\(model.bg.images.count) 张")
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("可以给 App 和小组件放自己喜欢的图片，几张图会定时轮换。")
                }

                Section {
                    Text("在主屏幕空白处长按 → 点左上角「编辑」→「添加小组件」→ 搜索「萤格」，有中号和大号两种。点小组件里的小圆圈会先问你「确认？」，再点一次才算完成，防止误触；事情多的时候点右边的 ▲▼ 翻页。")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    if !AppGroup.isShared {
                        Text("小组件暂时读不到 App 里的事项（共享数据的通道没有打开）。用 SideStore 重新安装一次通常就能好。")
                            .font(.footnote)
                            .foregroundStyle(Palette.now)
                    }
                } header: {
                    Text("小组件")
                }

                Section {
                    LabeledContent("名字", value: "萤格 GlowGrid")
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("事项只保存在这台手机里，不联网，也不需要账号。")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await model.refreshAuthorization() }
        }
    }
}
