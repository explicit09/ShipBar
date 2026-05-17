import Foundation
#if os(macOS)
import Security
#endif
import SwiftData

enum ShipBarModelContainer {
    static let cloudKitIdentifier = "iCloud.com.tadies.ShipBar"

    static var cloudKitDiagnostics: CloudKitDiagnostics {
        Self.diagnostics(
            containerIdentifiers: Self.entitlementStrings("com.apple.developer.icloud-container-identifiers"),
            services: Self.entitlementStrings("com.apple.developer.icloud-services"))
    }

    @MainActor
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ShipTask.self,
        ])
        let diagnostics = Self.cloudKitDiagnostics
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = if inMemory {
            .none
        } else if diagnostics.isEnabledForCurrentBuild {
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

    static func diagnostics(
        containerIdentifiers: [String],
        services: [String],
        containerIdentifier: String = Self.cloudKitIdentifier) -> CloudKitDiagnostics
    {
        let hasContainer = containerIdentifiers.contains(containerIdentifier)
        let hasCloudKitService = services.contains("CloudKit")
        let state: CloudKitAvailability
        if hasContainer, hasCloudKitService {
            state = .enabled
        } else if !hasContainer {
            state = .missingContainerEntitlement
        } else {
            state = .missingCloudKitService
        }

        return CloudKitDiagnostics(
            containerIdentifier: containerIdentifier,
            availability: state)
    }

    private static func entitlementStrings(_ key: String) -> [String] {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlement = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else {
            return []
        }

        if let values = entitlement as? [String] {
            return values
        }
        if let value = entitlement as? String {
            return [value]
        }
        return []
        #elseif os(iOS)
        #if targetEnvironment(simulator)
        return []
        #else
        switch key {
        case "com.apple.developer.icloud-container-identifiers":
            return [Self.cloudKitIdentifier]
        case "com.apple.developer.icloud-services":
            return ["CloudKit"]
        default:
            return []
        }
        #endif
        #else
        return []
        #endif
    }
}

enum CloudKitAvailability: Equatable {
    case enabled
    case missingContainerEntitlement
    case missingCloudKitService
}

struct CloudKitDiagnostics: Equatable {
    let containerIdentifier: String
    let availability: CloudKitAvailability

    var isEnabledForCurrentBuild: Bool {
        self.availability == .enabled
    }

    var statusText: String {
        self.isEnabledForCurrentBuild ? "Enabled" : "Local only"
    }

    var detailText: String {
        switch self.availability {
        case .enabled:
            "Private database: \(self.containerIdentifier)"
        case .missingContainerEntitlement:
            "Local storage is active because this build is missing the \(self.containerIdentifier) iCloud container entitlement."
        case .missingCloudKitService:
            "Local storage is active because this build is missing the CloudKit service entitlement."
        }
    }
}
