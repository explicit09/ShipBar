import SwiftData
import SwiftUI

@main
struct ShipBariOSApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try ShipBarModelContainer.make()
        } catch {
            print("Unable to create CloudKit-backed ShipBar model container: \(error)")
            self.modelContainer = try! ShipBarModelContainer.make(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ShipBarRootView()
        }
        .modelContainer(self.modelContainer)
    }
}
