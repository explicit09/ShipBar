import Foundation

enum ShipBarSyncTrigger: String, Sendable {
    case launch
    case becameActive
    case localMutation
    case sharedCaptureImport
    case manual
}

enum ShipBarSyncStatus: Equatable, Sendable {
    case idle
    case syncing(ShipBarSyncTrigger)
    case synced(Date)
    case failed(String)
}

actor ShipBarSyncCoordinator {
    typealias Operation = @Sendable () async throws -> Void

    private let operation: Operation
    private var isRunning = false
    private var needsFollowUp = false
    private(set) var status: ShipBarSyncStatus = .idle

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    func request(_ trigger: ShipBarSyncTrigger) async {
        if self.isRunning {
            self.needsFollowUp = true
            return
        }

        self.isRunning = true
        var nextTrigger = trigger
        repeat {
            self.needsFollowUp = false
            self.status = .syncing(nextTrigger)
            do {
                try await self.operation()
                self.status = .synced(.now)
            } catch {
                self.status = .failed(error.localizedDescription)
            }
            nextTrigger = .localMutation
        } while self.needsFollowUp
        self.isRunning = false
    }
}
