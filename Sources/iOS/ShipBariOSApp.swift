import Foundation
import SwiftData
import SwiftUI

@main
struct ShipBariOSApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try ShipBarModelContainer.make()
            let context = ModelContext(self.modelContainer)
            let projectCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? -1
            let taskCount = (try? context.fetchCount(FetchDescriptor<ShipTask>())) ?? -1
            Self.writeDiagnostic("ModelContainer OK. projects=\(projectCount) tasks=\(taskCount)")
        } catch {
            let message = "Unable to create CloudKit-backed ShipBar model container: \(error)"
            print(message)
            Self.writeDiagnostic(message)
            self.modelContainer = try! ShipBarModelContainer.make(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ShipBarRootView()
                .onAppear {
                    ShipBarDirectCloudSync.sync(modelContainer: self.modelContainer)
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
