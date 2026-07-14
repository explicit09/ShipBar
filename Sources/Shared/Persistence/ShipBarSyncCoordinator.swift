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

enum ShipBarSyncOutcome: Equatable, Sendable {
    case success
    case failure(String)
}

actor ShipBarSyncCoordinator {
    typealias Operation = @Sendable () async throws -> Void
    typealias OutcomeHandler = @Sendable (Set<String>, ShipBarSyncOutcome) async -> Void

    private let operation: Operation
    private let outcomeHandler: OutcomeHandler
    private var isRunning = false
    private var needsFollowUp = false
    private var pendingCaptureIDs: Set<String> = []
    private(set) var status: ShipBarSyncStatus = .idle

    init(
        operation: @escaping Operation,
        outcome: @escaping OutcomeHandler = { _, _ in }
    ) {
        self.operation = operation
        self.outcomeHandler = outcome
    }

    func request(_ trigger: ShipBarSyncTrigger, captureIDs: Set<String> = []) async {
        self.pendingCaptureIDs.formUnion(captureIDs)
        if self.isRunning {
            self.needsFollowUp = true
            return
        }

        self.isRunning = true
        var nextTrigger = trigger
        repeat {
            self.needsFollowUp = false
            let captureIDs = self.pendingCaptureIDs
            self.pendingCaptureIDs.removeAll()
            self.status = .syncing(nextTrigger)
            do {
                try await self.operation()
                self.status = .synced(.now)
                await self.outcomeHandler(captureIDs, .success)
            } catch {
                let message = error.localizedDescription
                self.status = .failed(message)
                await self.outcomeHandler(captureIDs, .failure(message))
            }
            nextTrigger = .localMutation
        } while self.needsFollowUp
        self.isRunning = false
    }
}
