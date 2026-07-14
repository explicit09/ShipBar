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
        let outcomes = SyncOutcomeProbe()
        let coordinator = ShipBarSyncCoordinator {
            throw TestSyncError.offline
        } outcome: { ids, outcome in
            await outcomes.record(ids: ids, outcome: outcome)
        }

        await coordinator.request(.manual, captureIDs: ["capture-1"])

        #expect(await coordinator.status == .failed("The Internet connection appears to be offline."))
        #expect(await outcomes.values == [
            SyncOutcomeProbe.Value(
                ids: ["capture-1"],
                outcome: .failure("The Internet connection appears to be offline.")),
        ])
    }

    @Test("coalesced requests retain capture ids through cloud outcomes")
    func coalescedCaptureOutcomes() async {
        let probe = SyncProbe()
        let outcomes = SyncOutcomeProbe()
        let coordinator = ShipBarSyncCoordinator {
            await probe.run()
        } outcome: { ids, outcome in
            await outcomes.record(ids: ids, outcome: outcome)
        }

        let first = Task { await coordinator.request(.sharedCaptureImport, captureIDs: ["first"]) }
        await probe.waitUntilStarted()
        await coordinator.request(.sharedCaptureImport, captureIDs: ["second"])
        await probe.release()
        await first.value

        #expect(await outcomes.values == [
            SyncOutcomeProbe.Value(ids: ["first"], outcome: .success),
            SyncOutcomeProbe.Value(ids: ["second"], outcome: .success),
        ])
    }
}

private actor SyncOutcomeProbe {
    struct Value: Equatable {
        let ids: Set<String>
        let outcome: ShipBarSyncOutcome
    }

    private(set) var values: [Value] = []

    func record(ids: Set<String>, outcome: ShipBarSyncOutcome) {
        self.values.append(Value(ids: ids, outcome: outcome))
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
