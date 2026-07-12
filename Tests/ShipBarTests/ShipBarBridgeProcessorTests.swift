import Foundation
import SwiftData
import Testing

@Suite("ShipBar bridge processor")
@MainActor
struct ShipBarBridgeProcessorTests {
    private struct Fixture {
        let processor: ShipBarBridgeProcessor
        let store: ShipBarBridgeStore
        let context: ModelContext
        let run: AgentRun
        let task: ShipTask
        let repoPath: String
    }

    private func makeFixture(runStatus: AgentRunStatus = .prepared) throws -> Fixture {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipbar-bridge-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        let task = ShipTask(title: "Ship the bridge", taskDescription: "Full details", prompt: "Do the work")
        context.insert(task)
        let run = AgentRun(
            taskID: task.id,
            projectID: nil,
            taskTitleSnapshot: task.title,
            projectNameSnapshot: nil,
            targetRawValue: AgentTarget.codex.rawValue,
            statusRawValue: runStatus.rawValue,
            promptSnapshot: "Frozen prompt",
            repositoryPathSnapshot: repoURL.path)
        context.insert(run)
        try context.save()

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipbar-bridge-proc-\(UUID().uuidString)")
        let store = try ShipBarBridgeStore(baseDirectory: base)
        let processor = ShipBarBridgeProcessor(
            store: store,
            modelContainer: container,
            contextOverride: context)
        return Fixture(processor: processor, store: store, context: context, run: run, task: task, repoPath: repoURL.path)
    }

    @Test("listPrepared returns prepared codex runs")
    func listPrepared() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(ShipBarBridgeRequest(command: .listPrepared))

        guard case .preparedRuns(let runs)? = response.result else {
            Issue.record("Expected prepared runs, got \(response)")
            return
        }
        #expect(runs.map(\.runID) == [fixture.run.id])
        #expect(runs.first?.taskTitle == "Ship the bridge")
        #expect(runs.first?.repositoryPath == fixture.repoPath)
    }

    @Test("getContext returns the frozen prompt and task description")
    func getContext() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .getContext(runID: fixture.run.id)))

        guard case .runContext(let context)? = response.result else {
            Issue.record("Expected run context, got \(response)")
            return
        }
        #expect(context.prompt == "Frozen prompt")
        #expect(context.taskDescription == "Full details")
        #expect(context.run.runID == fixture.run.id)
    }

    @Test("claim moves a prepared run to handed off")
    func claimTransitions() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .claim(runID: fixture.run.id)))

        #expect(response.isSuccess)
        #expect(fixture.run.status == .handedOff)
    }

    @Test("claim refuses a run whose repository is missing")
    func claimRefusesMissingRepo() throws {
        let fixture = try self.makeFixture()
        fixture.run.repositoryPathSnapshot = "/nonexistent/path/\(UUID().uuidString)"
        try fixture.context.save()

        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .claim(runID: fixture.run.id)))

        #expect(!response.isSuccess)
        #expect(fixture.run.status == .prepared)
    }

    @Test("invalid transitions are refused without mutation")
    func invalidTransitionRefused() throws {
        let fixture = try self.makeFixture(runStatus: .completed)
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .markRunning(runID: fixture.run.id)))

        #expect(!response.isSuccess)
        #expect(fixture.run.status == .completed)
    }

    @Test("missing runs produce an error response")
    func missingRun() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .claim(runID: "no-such-run")))

        #expect(!response.isSuccess)
        #expect(response.errorMessage?.contains("no-such-run") == true)
    }

    @Test("requestReview validates evidence and records the summary")
    func requestReview() throws {
        let fixture = try self.makeFixture(runStatus: .running)
        let evidence = "\(fixture.repoPath)/docs/reviews/run.html"
        let response = fixture.processor.process(ShipBarBridgeRequest(
            command: .requestReview(
                runID: fixture.run.id,
                summary: "Implemented and verified",
                evidencePaths: [evidence])))

        #expect(response.isSuccess)
        #expect(fixture.run.status == .needsReview)
        #expect(fixture.run.resultSummary == "Implemented and verified")
        #expect(fixture.run.evidenceURLString.contains("docs/reviews/run.html"))
    }

    @Test("requestReview rejects evidence outside the run repository")
    func requestReviewRejectsForeignEvidence() throws {
        let fixture = try self.makeFixture(runStatus: .running)
        let response = fixture.processor.process(ShipBarBridgeRequest(
            command: .requestReview(
                runID: fixture.run.id,
                summary: "Looks done",
                evidencePaths: ["/etc/passwd"])))

        #expect(!response.isSuccess)
        #expect(fixture.run.status == .running)
    }

    @Test("markFailed and cancel record their messages")
    func failAndCancel() throws {
        let failed = try self.makeFixture(runStatus: .running)
        let failResponse = failed.processor.process(ShipBarBridgeRequest(
            command: .markFailed(runID: failed.run.id, message: "Build broke")))
        #expect(failResponse.isSuccess)
        #expect(failed.run.status == .failed)
        #expect(failed.run.errorMessage == "Build broke")

        let canceled = try self.makeFixture(runStatus: .handedOff)
        let cancelResponse = canceled.processor.process(ShipBarBridgeRequest(
            command: .cancel(runID: canceled.run.id, message: "Superseded")))
        #expect(cancelResponse.isSuccess)
        #expect(canceled.run.status == .canceled)
    }

    @Test("duplicate requests are not reprocessed")
    func duplicateRequestsSkipped() async throws {
        let fixture = try self.makeFixture()
        let request = ShipBarBridgeRequest(command: .claim(runID: fixture.run.id))
        _ = try fixture.store.append(request)

        #expect(try fixture.processor.processPending() == 1)
        #expect(fixture.run.status == .handedOff)

        _ = try fixture.store.append(ShipBarBridgeRequest(id: request.id, command: request.command))
        #expect(try fixture.processor.processPending() == 0)
        #expect(fixture.run.status == .handedOff)
    }

    @Test("processPending answers requests and clears the queue")
    func processPendingAnswers() async throws {
        let fixture = try self.makeFixture()
        let request = ShipBarBridgeRequest(command: .listPrepared)
        _ = try fixture.store.append(request)

        #expect(try fixture.processor.processPending() == 1)
        #expect(try fixture.store.pendingRequests().isEmpty)
        let response = try fixture.store.response(for: request.id)
        #expect(response?.isSuccess == true)
    }
}
