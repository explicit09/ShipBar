import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ShipBarSyncMonitor {
    private(set) var status: ShipBarSyncStatus = .idle
    private(set) var currentRequest: Task<Void, Never>?

    private let coordinator: ShipBarSyncCoordinator

    init(
        operation: @escaping ShipBarSyncCoordinator.Operation,
        outcome: @escaping ShipBarSyncCoordinator.OutcomeHandler = { _, _ in }
    ) {
        self.coordinator = ShipBarSyncCoordinator(operation: operation, outcome: outcome)
    }

    static func direct(modelContainer: ModelContainer) -> ShipBarSyncMonitor {
        ShipBarSyncMonitor {
            _ = try await ShipBarDirectCloudSync.syncOnce(modelContainer: modelContainer)
        } outcome: { captureIDs, outcome in
            switch outcome {
            case .success:
                if !captureIDs.isEmpty {
                    try? SharedCaptureStore.markSyncedInSharedContainer(captureIDs)
                }
                // Every successful reconciliation enforces the diagnostics
                // window, even when that pass did not include new captures.
                _ = try? SharedCaptureStore.pruneTerminalInSharedContainer()
            case let .failure(message):
                guard !captureIDs.isEmpty else { return }
                try? SharedCaptureStore.markSyncFailedInSharedContainer(
                    captureIDs,
                    error: "iCloud sync failed: \(message)")
            }
        }
    }

    @discardableResult
    func request(
        _ trigger: ShipBarSyncTrigger,
        captureIDs: Set<String> = []
    ) -> Task<Void, Never> {
        let coordinator = self.coordinator
        let task = Task {
            self.status = .syncing(trigger)
            await coordinator.request(trigger, captureIDs: captureIDs)
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

    @discardableResult
    static func notify(_ trigger: ShipBarSyncTrigger, captureIDs: Set<String> = []) -> Bool {
        guard let monitor = self.monitor else { return false }
        monitor.request(trigger, captureIDs: captureIDs)
        return true
    }
}
