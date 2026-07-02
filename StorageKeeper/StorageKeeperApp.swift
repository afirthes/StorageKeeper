import SwiftUI

@main
struct StorageKeeperApp: App {
    @StateObject private var store = StorageViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
