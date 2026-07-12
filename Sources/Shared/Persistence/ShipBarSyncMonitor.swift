import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ShipBarSyncMonitor {
    private(set) var status: ShipBarSyncStatus = .idle
    private(set) var currentRequest: Task<Void, Never>?

    private let coordinator: ShipBarSyncCoordinator

    init(operation: @escaping ShipBarSyncCoordinator.Operation) {
        self.coordinator = ShipBarSyncCoordinator(operation: operation)
    }

    static func direct(modelContainer: ModelContainer) -> ShipBarSyncMonitor {
        ShipBarSyncMonitor {
            _ = try await ShipBarDirectCloudSync.syncOnce(modelContainer: modelContainer)
        }
    }

    @discardableResult
    func request(_ trigger: ShipBarSyncTrigger) -> Task<Void, Never> {
        let coordinator = self.coordinator
        let task = Task {
            self.status = .syncing(trigger)
            await coordinator.request(trigger)
            self.status = await coordinator.status
        }
        self.currentRequest = task
        return task
    }
}

@MainActor
enum ShipBarSyncHub {
    private(set) static var monitor: ShipBarSyncMonitor?

    static func configure(_ monitor: ShipBarSyncMonitor?) {
        self.monitor = monitor
    }

    @discardableResult
    static func configureDirect(modelContainer: ModelContainer) -> ShipBarSyncMonitor {
        if let monitor { return monitor }
        let monitor = ShipBarSyncMonitor.direct(modelContainer: modelContainer)
        self.monitor = monitor
        return monitor
    }

    static func notify(_ trigger: ShipBarSyncTrigger) {
        self.monitor?.request(trigger)
    }
}
