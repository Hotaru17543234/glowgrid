import SwiftUI

@main
struct TwinGlowApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
