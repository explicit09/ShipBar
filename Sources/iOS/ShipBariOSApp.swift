import Foundation
import SwiftData
import SwiftUI

@main
struct ShipBariOSApp: App {
    private let modelContainer: ModelContainer

    init() {
        self.modelContainer = Self.makeModelContainer()
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            let modelContainer = try ShipBarModelContainer.make()
            let context = ModelContext(modelContainer)
            let projectCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? -1
            let taskCount = (try? context.fetchCount(FetchDescriptor<ShipTask>())) ?? -1
            Self.writeDiagnostic("ModelContainer OK. projects=\(projectCount) tasks=\(taskCount)")
            return modelContainer
        } catch {
            let message = "Unable to create CloudKit-backed ShipBar model container: \(error)"
            print(message)
            Self.writeDiagnostic(message)
            do {
                return try ShipBarModelContainer.make(inMemory: true)
            } catch {
                fatalError("Unable to create fallback in-memory ShipBar model container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ShipBarRootView()
                .task {
                    ShipBarSyncHub.configureDirect(modelContainer: self.modelContainer).request(.launch)
                }
        }
        .modelContainer(self.modelContainer)
    }

    private static func writeDiagnostic(_ message: String) {
        let supportURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let body = """
        \(Date())
        \(message)
        """
        try? body.write(
            to: supportURL.appendingPathComponent("ShipBarDiagnostics.txt"),
            atomically: true,
            encoding: .utf8)
    }
}
