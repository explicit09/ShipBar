import CloudKit
import Foundation
import Testing

@Suite("ShipBar sync monitor")
@MainActor
struct ShipBarSyncMonitorTests {
    @Test("successful request ends in a synced status")
    func successfulRequestSyncs() async {
        let monitor = ShipBarSyncMonitor(operation: {})

        await monitor.request(.launch).value

        if case .synced = monitor.status {} else {
            Issue.record("Expected synced, got \(monitor.status)")
        }
    }

    @Test("failed request surfaces the error message")
    func failedRequestSurfacesError() async {
        let monitor = ShipBarSyncMonitor(operation: {
            throw MonitorTestError.offline
        })

        await monitor.request(.manual).value

        #expect(monitor.status == .failed("The Internet connection appears to be offline."))
    }

    @Test("overlapping requests coalesce through the shared coordinator")
    func overlappingRequestsCoalesce() async {
        let counter = OperationCounter()
        let monitor = ShipBarSyncMonitor(operation: {
            await counter.enter()
        })

        let first = monitor.request(.launch)
        await counter.waitUntilStarted()
        let second = monitor.request(.localMutation)
        await counter.release()
        await first.value
        await second.value

        #expect(await counter.count == 2)
        if case .synced = monitor.status {} else {
            Issue.record("Expected synced, got \(monitor.status)")
        }
    }
}

@Suite("ShipBar sync hub")
@MainActor
struct ShipBarSyncHubTests {
    @Test("notify forwards local mutations to the configured monitor")
    func notifyForwardsToMonitor() async {
        let monitor = ShipBarSyncMonitor(operation: {})
        ShipBarSyncHub.configure(monitor)
        defer { ShipBarSyncHub.configure(nil) }

        ShipBarSyncHub.notify(.localMutation)
        await monitor.currentRequest?.value

        if case .synced = monitor.status {} else {
            Issue.record("Expected synced, got \(monitor.status)")
        }
    }

    @Test("notify without a configured monitor is a safe no-op")
    func notifyWithoutMonitor() {
        ShipBarSyncHub.configure(nil)
        ShipBarSyncHub.notify(.localMutation)
    }
}

@Suite("ShipBar sync status display")
struct ShipBarSyncStatusDisplayTests {
    @Test("each status maps to a truthful settings row")
    func statusText() {
        #expect(ShipBarSyncStatus.idle.statusText == "Waiting")
        #expect(ShipBarSyncStatus.syncing(.launch).statusText == "Syncing")
        #expect(ShipBarSyncStatus.synced(.now).statusText == "Synced")
        #expect(ShipBarSyncStatus.failed("Offline").statusText == "Needs attention")
    }

    @Test("detail text explains the state without inventing success")
    func detailText() {
        #expect(ShipBarSyncStatus.idle.detailText == "No sync has run yet this session.")
        #expect(ShipBarSyncStatus.syncing(.manual).detailText == "Syncing with iCloud now.")
        #expect(ShipBarSyncStatus.synced(.now).detailText.hasPrefix("Last synced"))
        #expect(ShipBarSyncStatus.failed("Offline").detailText == "Offline")
    }
}

@Suite("Direct sync error classification")
struct DirectSyncErrorClassificationTests {
    @Test("a missing manifest record is first-sync state, not a failure")
    func missingRecordIsNotFailure() {
        #expect(ShipBarDirectCloudSync.isMissingRecordError(CKError(.unknownItem)))
    }

    @Test("network and other errors stay failures")
    func otherErrorsAreFailures() {
        #expect(!ShipBarDirectCloudSync.isMissingRecordError(CKError(.networkUnavailable)))
        #expect(!ShipBarDirectCloudSync.isMissingRecordError(MonitorTestError.offline))
    }
}

private enum MonitorTestError: LocalizedError {
    case offline

    var errorDescription: String? {
        "The Internet connection appears to be offline."
    }
}

private actor OperationCounter {
    private(set) var count = 0
    private var started = false
    private var released = false

    func enter() async {
        self.count += 1
        self.started = true
        while !self.released, self.count == 1 {
            await Task.yield()
        }
    }

    func waitUntilStarted() async {
        while !self.started { await Task.yield() }
    }

    func release() {
        self.released = true
    }
}
