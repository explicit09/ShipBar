import Foundation
import SwiftData

enum ShipBarModelContainer {
    static let cloudKitIdentifier = "iCloud.com.tadies.ShipBar"

    @MainActor
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ShipTask.self,
        ])
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = if inMemory {
            .none
        } else if Self.hasCloudKitEntitlement {
            .private(Self.cloudKitIdentifier)
        } else {
            .none
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static var hasCloudKitEntitlement: Bool {
        // Unsigned local debug builds can crash during asynchronous CloudKit setup.
        // Release builds keep CloudKit enabled through the configured entitlements.
        #if DEBUG
        false
        #else
        true
        #endif
    }
}
