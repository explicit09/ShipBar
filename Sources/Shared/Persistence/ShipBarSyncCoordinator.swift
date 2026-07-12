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

    var statusText: String {
        switch self {
        case .idle: "Waiting"
        case .syncing: "Syncing"
        case .synced: "Synced"
        case .failed: "Needs attention"
        }
    }

    var detailText: String {
        switch self {
        case .idle: "No sync has run yet this session."
        case .syncing: "Syncing with iCloud now."
        case .synced(let date): "Last synced \(date.formatted(date: .omitted, time: .shortened))."
        case .failed(let message): message
        }
    }
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
