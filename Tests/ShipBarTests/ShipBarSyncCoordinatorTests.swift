import Foundation
import Testing

@Suite("ShipBar sync coordinator")
struct ShipBarSyncCoordinatorTests {
    @Test("overlapping requests coalesce into one follow-up pass")
    func overlappingRequestsCoalesce() async {
        let probe = SyncProbe()
        let coordinator = ShipBarSyncCoordinator {
            await probe.run()
        }

        let first = Task { await coordinator.request(.launch) }
        await probe.waitUntilStarted()
        await coordinator.request(.becameActive)
        await probe.release()
        await first.value

        #expect(await probe.runCount == 2)
        if case .synced = await coordinator.status {} else {
            Issue.record("Expected a synced status")
        }
    }

    @Test("failure exposes an actionable status")
    func failureStatus() async {
        let coordinator = ShipBarSyncCoordinator {
            throw TestSyncError.offline
        }

        await coordinator.request(.manual)

        #expect(await coordinator.status == .failed("The Internet connection appears to be offline."))
    }
}

private actor SyncProbe {
    private(set) var runCount = 0
    private var started = false
    private var released = false

    func run() async {
        self.runCount += 1
        self.started = true
        while !self.released, self.runCount == 1 {
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

private enum TestSyncError: LocalizedError {
    case offline

    var errorDescription: String? {
        "The Internet connection appears to be offline."
    }
}
