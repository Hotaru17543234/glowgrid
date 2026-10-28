import SwiftUI

struct AccountManagerView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(store.accounts) { account in
                        NavigationLink(value: account.id) {
                            AccountRow(account: account, current: account.id == store.selectedID)
                        }
                    }
                    .onMove { source, destination in
                        store.move(from: source, to: destination)
                    }
                } footer: {
                    Text("每个账号都有自己独立的网页数据（登录状态、Cookie），互不干扰。切到另一个号时，这个号的页面会留在后台，切回来还在原来的地方。")
                }

                Section {
                    Button {
                        let id = store.addAccount()
                        path.append(id)
                    } label: {
                        Label("添加账号", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                AccountEditView(accountID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(account.color)
                .frame(width: 12, height: 12)
                .shadow(color: account.color.opacity(0.8), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.rounded(17, .medium))
                    .foregroundStyle(Theme.ink)
                Text(account.home.host() ?? account.homeURL)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if current {
                Text("正在看")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(account.color.opacity(0.25))
                    }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AccountEditView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    let accountID: UUID

    @State private var name = ""
    @State private var homeText = ""
    @State private var confirmClear = false
    @State private var confirmDelete = false
    @State private var cleared = false

    var body: some View {
        Form {
            if let account = store.account(accountID) {
                Section("名字") {
                    TextField("比如 主号、学习号", text: $name)
                        .onSubmit(commitName)
                }

                Section("颜色") {
                    HStack(spacing: 14) {
                        ForEach(Glow.allCases) { glow in
                            Button {
                                store.update(accountID) { $0.glow = glow.rawValue }
                            } label: {
                                Circle()
                                    .fill(glow.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Circle().strokeBorder(Theme.ink,
                                                              lineWidth: account.glow == glow.rawValue ? 2.5 : 0)
                                    }
                                    .shadow(color: glow.color.opacity(account.glow == glow.rawValue ? 0.8 : 0),
                                            radius: 5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(glow.name)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("https://muse.ai", text: $homeText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(commitHome)
                } header: {
                    Text("主页")
                } footer: {
                    Text("点底部的小房子会回到这里。")
                }

                Section {
                    Button("退出登录（清除这个号的网页数据）", role: .destructive) {
                        confirmClear = true
                    }
                    if store.accounts.count > 1 {
                        Button("从双萤里删除这个号", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                } footer: {
                    if cleared {
                        Text("已经清除好啦，回到这个号就能重新登录。")
                    } else {
                        Text("只影响这个号在双萤里的数据，Muse 账号本身不会被删除。")
                    }
                }
            }
        }
        .navigationTitle(store.account(accountID)?.name ?? "账号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = store.account(accountID)?.name ?? ""
            homeText = store.account(accountID)?.homeURL ?? ""
        }
        .onDisappear {
            commitName()
            commitHome()
        }
        .confirmationDialog("要退出这个号吗？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除并退出登录", role: .destructive) {
                Task {
                    await store.clearData(accountID)
                    cleared = true
                }
            }
        } message: {
            Text("会删除这个号的登录状态、Cookie 和缓存，之后需要重新登录。其他号不受影响。")
        }
        .confirmationDialog("从双萤里删除这个号？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let id = accountID
                dismiss()
                Task {
                    await store.delete(id)
                }
            }
        } message: {
            Text("这个号在双萤里的登录数据会一起删掉。Muse 账号本身不会被删除。")
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = store.account(accountID)?.name ?? name
            return
        }
        store.update(accountID) { $0.name = trimmed }
    }

    private func commitHome() {
        guard let url = Account.normalizedURL(homeText) else {
            homeText = store.account(accountID)?.homeURL ?? homeText
            return
        }
        store.update(accountID) { $0.homeURL = url.absoluteString }
        homeText = url.absoluteString
    }
}
