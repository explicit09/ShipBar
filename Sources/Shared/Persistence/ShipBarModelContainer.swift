import Foundation
import SwiftData

enum ShipBarModelContainer {
    static let cloudKitIdentifier = "iCloud.com.tadies.ShipBar"

    static var cloudKitDiagnostics: CloudKitDiagnostics {
        CloudKitDiagnostics(
            containerIdentifier: Self.cloudKitIdentifier,
            isEnabledForCurrentBuild: Self.hasCloudKitEntitlement)
    }

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

struct CloudKitDiagnostics: Equatable {
    let containerIdentifier: String
    let isEnabledForCurrentBuild: Bool

    var statusText: String {
        self.isEnabledForCurrentBuild ? "Enabled" : "Disabled for debug build"
    }

    var detailText: String {
        self.isEnabledForCurrentBuild
            ? "Private database: \(self.containerIdentifier)"
            : "Local debug storage is active. Signed app builds use \(self.containerIdentifier)."
    }
}
