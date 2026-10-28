import Foundation
import SwiftUI
import WebKit

/// One signed-in identity. Its `id` also names its own WebKit data store,
/// so every account keeps separate cookies, local storage and cache.
struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var glow: Int
    var homeURL: String

    static let defaultHome = URL(string: "https://muse.ai")!

    var color: Color { (Glow(rawValue: glow) ?? .firefly).color }
    var home: URL { Account.normalizedURL(homeURL) ?? Account.defaultHome }

    /// Turns "muse.ai" or " https://muse.ai/ " into a usable web address, or nil if it isn't one.
    static func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil else { return nil }
        return url
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var selectedID: UUID

    /// One live web view per account. Kept alive while switching, so the other account
    /// stays signed in and its page is still where you left it.
    private var tabs: [UUID: WebTab] = [:]

    private static let accountsKey = "twinglow.accounts.v1"
    private static let selectedKey = "twinglow.selected.v1"

    init() {
        let defaults = UserDefaults.standard
        var loaded: [Account] = []
        if let data = defaults.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            loaded = decoded
        }
        if loaded.isEmpty {
            let home = Account.defaultHome.absoluteString
            loaded = [
                Account(id: UUID(), name: "A 号", glow: Glow.firefly.rawValue, homeURL: home),
                Account(id: UUID(), name: "B 号", glow: Glow.sky.rawValue, homeURL: home),
            ]
        }
        let savedSelected = defaults.string(forKey: Self.selectedKey).flatMap { UUID(uuidString: $0) }
        // selectedID first: it is the only stored property without a default value,
        // so `self` is fully initialised once it is set.
        selectedID = loaded.first(where: { $0.id == savedSelected })?.id ?? loaded[0].id
        accounts = loaded
        save()
        // Open every account right away so all of them stay signed in from launch.
        for account in loaded {
            _ = tab(for: account.id)
        }
    }

    var selected: Account {
        accounts.first(where: { $0.id == selectedID }) ?? accounts[0]
    }

    func account(_ id: UUID) -> Account? {
        accounts.first(where: { $0.id == id })
    }

    func tab(for id: UUID) -> WebTab {
        let account = accounts.first(where: { $0.id == id }) ?? accounts[0]
        if let existing = tabs[account.id] {
            return existing
        }
        let tab = WebTab(account: account)
        tabs[account.id] = tab
        return tab
    }

    func select(_ id: UUID) {
        guard accounts.contains(where: { $0.id == id }), id != selectedID else { return }
        selectedID = id
        save()
    }

    func update(_ id: UUID, _ change: (inout Account) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var account = accounts[index]
        change(&account)
        guard account != accounts[index] else { return }
        accounts[index] = account
        tabs[id]?.updateHome(account.home)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Adds an account with the next free letter and colour, and returns its id.
    @discardableResult
    func addAccount() -> UUID {
        let usedGlows = Set(accounts.map(\.glow))
        let glow = Glow.allCases.first(where: { !usedGlows.contains($0.rawValue) })
            ?? Glow.allCases[accounts.count % Glow.allCases.count]
        let usedNames = Set(accounts.map(\.name))
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        let name = letters.map { "\($0) 号" }.first(where: { !usedNames.contains($0) })
            ?? "第 \(accounts.count + 1) 个号"
        let account = Account(id: UUID(), name: name, glow: glow.rawValue,
                              homeURL: Account.defaultHome.absoluteString)
        accounts.append(account)
        save()
        _ = tab(for: account.id)
        return account.id
    }

    /// Signs the account out by wiping its own web data. Other accounts are untouched.
    func clearData(_ id: UUID) async {
        let webTab = self.tab(for: id)
        let dataStore = webTab.webView.configuration.websiteDataStore
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                   modifiedSince: Date.distantPast)
        webTab.goHome()
    }

    /// Removes the account from TwinGlow and deletes its web data from the phone.
    /// (The Muse account itself is not touched.)
    func delete(_ id: UUID) async {
        guard accounts.count > 1, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        if selectedID == id {
            selectedID = accounts[index == 0 ? 1 : index - 1].id
        }
        accounts.remove(at: index)
        save()
        if let tab = tabs.removeValue(forKey: id) {
            tab.tearDown()
        }
        // WebKit only deletes a data store that no web view is using any more,
        // so give it a moment to let go first.
        try? await Task.sleep(nanoseconds: 800_000_000)
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Self.accountsKey)
        }
        defaults.set(selectedID.uuidString, forKey: Self.selectedKey)
    }
}
