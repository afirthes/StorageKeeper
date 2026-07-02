import SwiftData
import SwiftUI

@main
struct StorageKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            StorageContainer.self,
            StoredItem.self,
            StorageTag.self,
            TagAssignment.self
        ])
    }
}
