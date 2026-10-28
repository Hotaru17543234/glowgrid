import SwiftUI
import UIKit
import WebKit

struct RootView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var showManager = false

    var body: some View {
        let tab = store.tab(for: store.selectedID)
        VStack(spacing: 0) {
            AccountBar(showManager: $showManager)
            TabPane(tab: tab)
                .id(tab.accountID)
        }
        .background(Theme.paper.ignoresSafeArea())
        // Let the page handle the keyboard itself, the way Safari does.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showManager) {
            AccountManagerView()
                .environmentObject(store)
        }
    }
}

// MARK: - Account switcher

private struct AccountBar: View {
    @EnvironmentObject private var store: AccountStore
    @Binding var showManager: Bool

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.accounts) { account in
                        AccountChip(account: account, selected: account.id == store.selectedID)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Button {
                showManager = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 40)
            }
            .accessibilityLabel("管理账号")
            .padding(.trailing, 6)
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }
}

private struct AccountChip: View {
    @EnvironmentObject private var store: AccountStore
    let account: Account
    let selected: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                store.select(account.id)
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(account.color)
                    .frame(width: 9, height: 9)
                    .shadow(color: account.color.opacity(selected ? 0.9 : 0), radius: 4)
                Text(account.name)
                    .font(.rounded(15, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(selected ? account.color.opacity(0.22) : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(selected ? account.color : Theme.line, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.tab(for: account.id).goHome()
            } label: {
                Label("回到主页", systemImage: "house")
            }
            Button {
                store.tab(for: account.id).retry()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }
}

// MARK: - One account's browser

private struct TabPane: View {
    @ObservedObject var tab: WebTab

    var body: some View {
        VStack(spacing: 0) {
            ProgressLine(progress: tab.progress, visible: tab.isLoading)
            ZStack {
                WebViewHost(webView: tab.webView)
                if let message = tab.loadError {
                    LoadErrorCard(message: message) {
                        tab.retry()
                    }
                    .padding(24)
                }
            }
            BrowserBar(tab: tab)
        }
        .sheet(item: $tab.popup) { popup in
            PopupSheet(popup: popup) {
                tab.closePopup()
            }
        }
    }
}

private struct ProgressLine: View {
    let progress: Double
    let visible: Bool

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.glow)
                .frame(width: geo.size.width * max(0.06, min(progress, 1)))
                .shadow(color: Theme.glow.opacity(0.8), radius: 3)
        }
        .frame(height: 2)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: progress)
        .animation(.easeOut(duration: 0.3), value: visible)
    }
}

private struct BrowserBar: View {
    @ObservedObject var tab: WebTab

    var body: some View {
        HStack(spacing: 0) {
            barButton("chevron.backward", label: "后退", enabled: tab.canGoBack) {
                tab.webView.goBack()
            }
            Spacer(minLength: 0)
            barButton("chevron.forward", label: "前进", enabled: tab.canGoForward) {
                tab.webView.goForward()
            }
            Spacer(minLength: 0)
            barButton("house", label: "回到主页", enabled: true) {
                tab.goHome()
            }
            Spacer(minLength: 0)
            barButton(tab.isLoading ? "xmark" : "arrow.clockwise",
                      label: tab.isLoading ? "停止" : "刷新", enabled: true) {
                tab.reloadOrStop()
            }
            Spacer(minLength: 0)
            barButton("safari", label: "在 Safari 打开", enabled: tab.currentURL != nil) {
                tab.openInSafari(tab.currentURL)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }

    private func barButton(_ symbol: String, label: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(enabled ? Theme.ink : Theme.muted.opacity(0.45))
                .frame(width: 44, height: 40)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct LoadErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("没有连上呢")
                .font(.rounded(18, .semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("再试一次")
                    .font(.rounded(16, .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background {
                        Capsule().fill(Theme.glow.opacity(0.35))
                    }
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial)
        }
    }
}

// MARK: - Pop-up windows

private struct PopupSheet: View {
    let popup: PopupWindow
    let close: () -> Void

    var body: some View {
        NavigationStack {
            WebViewHost(webView: popup.webView)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle("新窗口")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: close)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let url = popup.webView.url {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("在 Safari 打开")
                    }
                }
        }
    }
}
