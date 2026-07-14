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

    private func makeFixture(
        runStatus: AgentRunStatus = .prepared,
        saveSucceeds: Bool = true) throws -> Fixture
    {
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
            contextOverride: context,
            persistenceOperation: { _, _ in saveSucceeds })
        return Fixture(processor: processor, store: store, context: context, run: run, task: task, repoPath: repoURL.path)
    }

    @Test("maintenance reset removes every project, task, and run while retaining sync tombstones")
    func maintenanceResetClearsAllUserData() throws {
        let fixture = try self.makeFixture()
        let project = Project(name: "Temporary project")
        let projectTask = ShipTask(title: "Temporary project task", project: project)
        fixture.context.insert(project)
        fixture.context.insert(projectTask)
        try fixture.context.save()

        let response = fixture.processor.process(ShipBarBridgeRequest(command: .resetAllData(
            confirmation: "RESET SHIPBAR")))

        #expect(response.isSuccess)
        #expect(try fixture.context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<ShipTask>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AgentRun>()).isEmpty)
        let tombstones = try fixture.context.fetch(FetchDescriptor<ShipBarDeletionTombstone>())
        #expect(Set(tombstones.map(\.recordKind)) == Set(["project", "task", "run"]))
    }

    @Test("productivity commands create, update, trash, restore, and permanently delete a task")
    func taskProductivityLifecycle() throws {
        let fixture = try self.makeFixture()
        let create = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "create-task-1",
            command: ShipBarProductivityCommand(
                kind: .createTask,
                task: ShipBarTaskPatch(
                    title: "Full productivity probe",
                    description: "Keep all supplied context",
                    prompt: "Verify every acceptance criterion",
                    status: "todo",
                    priority: "high",
                    type: "feature",
                    sourceApp: "ChatGPT",
                    sourceURL: "https://chatgpt.com/")))))

        guard case .commandResult(let created)? = create.result,
              let taskID = created.task?.taskID,
              let revision = created.task?.revision else {
            Issue.record("Expected created task command result")
            return
        }
        #expect(created.status == "applied")
        #expect(created.task?.taskDescription == "Keep all supplied context")
        #expect(created.task?.prompt == "Verify every acceptance criterion")
        #expect(created.task?.sourceApp == "ChatGPT")
        #expect(created.task?.sourceURL == "https://chatgpt.com/")

        let update = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "update-task-1",
            command: ShipBarProductivityCommand(
                kind: .updateTask,
                recordID: taskID,
                expectedRevision: revision,
                task: ShipBarTaskPatch(status: "doing", focusDate: "2026-07-14", focusOrder: 2)))))
        guard case .commandResult(let updated)? = update.result else {
            Issue.record("Expected updated task command result")
            return
        }
        #expect(updated.task?.status == "doing")
        #expect(updated.task?.focusOrder == 2)

        let trash = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "trash-task-1",
            command: ShipBarProductivityCommand(
                kind: .trashTask,
                recordID: taskID,
                expectedRevision: updated.task?.revision))))
        guard case .commandResult(let trashed)? = trash.result else {
            Issue.record("Expected trashed task command result")
            return
        }
        #expect(trashed.task?.trashedAt != nil)

        let refused = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "delete-active-task",
            command: ShipBarProductivityCommand(
                kind: .permanentlyDeleteTask,
                recordID: fixture.task.id,
                expectedRevision: fixture.task.revision))))
        #expect(!refused.isSuccess)

        let restore = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "restore-task-1",
            command: ShipBarProductivityCommand(
                kind: .restoreTask,
                recordID: taskID,
                expectedRevision: trashed.task?.revision))))
        guard case .commandResult(let restored)? = restore.result else {
            Issue.record("Expected restored task command result")
            return
        }
        #expect(restored.task?.trashedAt == nil)

        let retrash = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "trash-task-2",
            command: ShipBarProductivityCommand(
                kind: .trashTask,
                recordID: taskID,
                expectedRevision: restored.task?.revision))))
        guard case .commandResult(let retrashResult)? = retrash.result else {
            Issue.record("Expected re-trashed task command result")
            return
        }
        let deleted = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "delete-task-1",
            command: ShipBarProductivityCommand(
                kind: .permanentlyDeleteTask,
                recordID: taskID,
                expectedRevision: retrashResult.task?.revision))))
        #expect(deleted.isSuccess)
        #expect(try fixture.context.fetch(FetchDescriptor<ShipTask>()).contains { $0.id == taskID } == false)
    }

    @Test("project productivity lifecycle preserves task safety and rejects stale revisions")
    func projectProductivityLifecycle() throws {
        let fixture = try self.makeFixture()
        let create = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "create-project-1",
            command: ShipBarProductivityCommand(
                kind: .createProject,
                project: ShipBarProjectPatch(
                    name: "ChatGPT QA",
                    outcome: "Prove complete productivity parity",
                    basePrompt: "Preserve evidence",
                    repoPath: fixture.repoPath,
                    color: "purple",
                    icon: "checkmark.seal")))))
        guard case .commandResult(let created)? = create.result,
              let projectID = created.project?.projectID,
              let revision = created.project?.revision else {
            Issue.record("Expected created project")
            return
        }

        let stale = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "stale-project",
            command: ShipBarProductivityCommand(
                kind: .updateProject,
                recordID: projectID,
                expectedRevision: revision + 99,
                project: ShipBarProjectPatch(outcome: "Wrong")))))
        #expect(!stale.isSuccess)
        #expect(stale.errorMessage?.contains("conflict") == true)

        let trash = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "trash-project-1",
            command: ShipBarProductivityCommand(
                kind: .trashProject,
                recordID: projectID,
                expectedRevision: revision,
                taskHandling: "move_tasks_to_inbox"))))
        guard case .commandResult(let trashed)? = trash.result else {
            Issue.record("Expected trashed project")
            return
        }
        #expect(trashed.project?.trashedAt != nil)

        let restore = fixture.processor.process(ShipBarBridgeRequest(command: .applyProductivity(
            commandID: "restore-project-1",
            command: ShipBarProductivityCommand(
                kind: .restoreProject,
                recordID: projectID,
                expectedRevision: trashed.project?.revision))))
        #expect(restore.isSuccess)
    }

    @Test("preparation and capture return failure and roll back when persistence fails")
    func creationSaveFailureRollsBack() throws {
        let prepared = try self.makeFixture(saveSucceeds: false)
        let prepareResponse = prepared.processor.process(ShipBarBridgeRequest(command: .prepareRun(
            taskID: prepared.task.id,
            repositoryPath: prepared.repoPath,
            instructions: "",
            preparationKey: "failed-preparation")))
        #expect(!prepareResponse.isSuccess)
        #expect(prepareResponse.errorMessage?.contains("save") == true)
        #expect(try prepared.context.fetch(FetchDescriptor<AgentRun>())
            .filter { $0.preparationKey == "failed-preparation" }.isEmpty)

        let captured = try self.makeFixture(saveSucceeds: false)
        let captureResponse = captured.processor.process(ShipBarBridgeRequest(command: .queueCapture(
            captureID: "failed-capture", title: "Do not persist", description: "",
            projectName: nil, priority: "normal", dueAt: nil)))
        #expect(!captureResponse.isSuccess)
        #expect(try captured.context.fetch(FetchDescriptor<ShipTask>())
            .filter { $0.sourceCaptureID == "failed-capture" }.isEmpty)
    }

    @Test("every run mutation returns failure and rolls back when persistence fails")
    func allRunMutationSaveFailuresRollBack() throws {
        let claimed = try self.makeFixture(saveSucceeds: false)
        let claimResponse = claimed.processor.process(
            ShipBarBridgeRequest(command: .claim(runID: claimed.run.id)))
        #expect(!claimResponse.isSuccess)
        #expect(!claimed.context.hasChanges)
        let claimedFreshContext = ModelContext(claimed.processor.modelContainer)
        #expect(try claimedFreshContext.fetch(FetchDescriptor<AgentRun>())
            .first { $0.id == claimed.run.id }?.status == .prepared)

        let running = try self.makeFixture(runStatus: .handedOff, saveSucceeds: false)
        let runningResponse = running.processor.process(
            ShipBarBridgeRequest(command: .markRunning(runID: running.run.id)))
        #expect(!runningResponse.isSuccess)
        #expect(!running.context.hasChanges)
        let runningFreshContext = ModelContext(running.processor.modelContainer)
        #expect(try runningFreshContext.fetch(FetchDescriptor<AgentRun>())
            .first { $0.id == running.run.id }?.status == .handedOff)

        let reviewing = try self.makeFixture(runStatus: .running, saveSucceeds: false)
        let reviewResponse = reviewing.processor.process(ShipBarBridgeRequest(command: .requestReview(
            runID: reviewing.run.id,
            summary: "Ready",
            evidencePaths: [reviewing.repoPath + "/evidence.txt"])))
        #expect(!reviewResponse.isSuccess)
        #expect(!reviewing.context.hasChanges)
        let reviewingFreshContext = ModelContext(reviewing.processor.modelContainer)
        let unchangedReview = try reviewingFreshContext.fetch(FetchDescriptor<AgentRun>())
            .first { $0.id == reviewing.run.id }
        #expect(unchangedReview?.status == .running)
        #expect(unchangedReview?.resultSummary == "")
        #expect(unchangedReview?.evidenceURLString == "")

        let failed = try self.makeFixture(runStatus: .handedOff, saveSucceeds: false)
        let failedResponse = failed.processor.process(ShipBarBridgeRequest(command: .markFailed(
            runID: failed.run.id,
            message: "Do not persist")))
        #expect(!failedResponse.isSuccess)
        #expect(!failed.context.hasChanges)
        let failedFreshContext = ModelContext(failed.processor.modelContainer)
        let unchangedFailure = try failedFreshContext.fetch(FetchDescriptor<AgentRun>())
            .first { $0.id == failed.run.id }
        #expect(unchangedFailure?.status == .handedOff)
        #expect(unchangedFailure?.resultSummary == "")

        let canceled = try self.makeFixture(runStatus: .handedOff, saveSucceeds: false)
        let canceledResponse = canceled.processor.process(ShipBarBridgeRequest(command: .cancel(
            runID: canceled.run.id,
            message: "Do not persist")))
        #expect(!canceledResponse.isSuccess)
        #expect(!canceled.context.hasChanges)
        let canceledFreshContext = ModelContext(canceled.processor.modelContainer)
        let unchangedCancellation = try canceledFreshContext.fetch(FetchDescriptor<AgentRun>())
            .first { $0.id == canceled.run.id }
        #expect(unchangedCancellation?.status == .handedOff)
        #expect(unchangedCancellation?.resultSummary == "")
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

    @Test("cloud captures save exactly once by source capture ID")
    func queueCaptureIsIdempotent() throws {
        let fixture = try self.makeFixture()
        let command = ShipBarBridgeCommand.queueCapture(
            captureID: "cloud-capture-1",
            title: "Write the report",
            description: "Include the verified results",
            projectName: nil,
            priority: "high",
            dueAt: nil)

        let first = fixture.processor.process(ShipBarBridgeRequest(command: command))
        let second = fixture.processor.process(ShipBarBridgeRequest(command: command))

        guard case .tasks(let firstTasks)? = first.result,
              case .tasks(let secondTasks)? = second.result
        else {
            Issue.record("Expected task summaries for both deliveries")
            return
        }
        let matches = try fixture.context.fetch(FetchDescriptor<ShipTask>()).filter {
            $0.sourceCaptureID == "cloud-capture-1"
        }
        #expect(matches.count == 1)
        #expect(firstTasks.first?.taskID == secondTasks.first?.taskID)
        #expect(matches.first?.title == "Write the report")
        #expect(matches.first?.taskDescription == "Include the verified results")
        #expect(matches.first?.priority == .high)
        #expect(matches.first?.isInbox == true)
    }

    @Test("remote execution prepares a Codex run without claiming it")
    func prepareRemoteRun() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(ShipBarBridgeRequest(command: .prepareRun(
            taskID: fixture.task.id,
            repositoryPath: fixture.repoPath,
            instructions: "Run the focused tests")))

        guard case .runStatus(let run)? = response.result else {
            Issue.record("Expected a prepared run summary")
            return
        }
        #expect(run.taskID == fixture.task.id)
        #expect(run.status == AgentRunStatus.prepared.rawValue)
        let created = try fixture.context.fetch(FetchDescriptor<AgentRun>()).first { $0.id == run.runID }
        #expect(created?.repositoryPathSnapshot == fixture.repoPath)
        #expect(created?.promptSnapshot.contains("Run the focused tests") == true)
    }

    @Test("relay execution identity makes remote preparation idempotent")
    func prepareRemoteRunIsIdempotent() throws {
        let fixture = try self.makeFixture()
        let command = ShipBarBridgeCommand.prepareRun(
            taskID: fixture.task.id,
            repositoryPath: fixture.repoPath,
            instructions: "Run tests",
            preparationKey: "relay-execution-1")

        let first = fixture.processor.process(ShipBarBridgeRequest(command: command))
        let second = fixture.processor.process(ShipBarBridgeRequest(command: command))
        guard case .runStatus(let firstRun)? = first.result,
              case .runStatus(let secondRun)? = second.result else {
            Issue.record("Expected prepared run summaries")
            return
        }
        #expect(firstRun.runID == secondRun.runID)
        #expect(try fixture.context.fetch(FetchDescriptor<AgentRun>())
            .filter { $0.preparationKey == "relay-execution-1" }.count == 1)
    }

    @Test("searchTasks matches titles and descriptions without prompts")
    func searchTasks() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .searchTasks(query: "BRIDGE")))

        guard case .tasks(let tasks)? = response.result else {
            Issue.record("Expected tasks, got \(response)")
            return
        }
        #expect(tasks.map(\.taskID) == [fixture.task.id])
        #expect(tasks.first?.title == "Ship the bridge")

        let empty = fixture.processor.process(
            ShipBarBridgeRequest(command: .searchTasks(query: "nothing-matches-this")))
        guard case .tasks(let none)? = empty.result else {
            Issue.record("Expected empty tasks, got \(empty)")
            return
        }
        #expect(none.isEmpty)
    }

    @Test("productivity snapshot returns existing tasks and projects including Trash")
    func productivitySnapshot() throws {
        let fixture = try self.makeFixture()
        let project = Project(name: "Existing project", outcome: "Keep local work visible")
        project.trashedAt = .now
        fixture.context.insert(project)
        fixture.task.project = project
        fixture.task.isInbox = false
        try fixture.context.save()

        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .getProductivitySnapshot))

        guard case .productivitySnapshot(let snapshot)? = response.result else {
            Issue.record("Expected productivity snapshot, got \(response)")
            return
        }
        #expect(snapshot.tasks.map(\.taskID) == [fixture.task.id])
        #expect(snapshot.projects.map(\.projectID) == [project.id])
        #expect(snapshot.projects.first?.trashedAt != nil)
    }

    @Test("getToday returns only tasks focused on the current day")
    func getToday() throws {
        let fixture = try self.makeFixture()
        fixture.task.focusDate = Calendar.current.startOfDay(for: .now)
        fixture.task.focusOrder = 1
        let notToday = ShipTask(title: "Later work")
        fixture.context.insert(notToday)
        try fixture.context.save()

        let response = fixture.processor.process(ShipBarBridgeRequest(command: .getToday))

        guard case .tasks(let tasks)? = response.result else {
            Issue.record("Expected tasks, got \(response)")
            return
        }
        #expect(tasks.map(\.taskID) == [fixture.task.id])
    }

    @Test("getTask returns one task with its description")
    func getTask() throws {
        let fixture = try self.makeFixture()
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .getTask(taskID: fixture.task.id)))

        guard case .tasks(let tasks)? = response.result else {
            Issue.record("Expected tasks, got \(response)")
            return
        }
        #expect(tasks.first?.taskDescription == "Full details")

        let missing = fixture.processor.process(
            ShipBarBridgeRequest(command: .getTask(taskID: "no-such-task")))
        #expect(!missing.isSuccess)
    }

    @Test("getRunStatus reports state without the prompt body")
    func getRunStatus() throws {
        let fixture = try self.makeFixture(runStatus: .running)
        let response = fixture.processor.process(
            ShipBarBridgeRequest(command: .getRunStatus(runID: fixture.run.id)))

        guard case .runStatus(let summary)? = response.result else {
            Issue.record("Expected run status, got \(response)")
            return
        }
        #expect(summary.runID == fixture.run.id)
        #expect(summary.status == AgentRunStatus.running.rawValue)
        let encoded = try String(decoding: JSONEncoder().encode(summary), as: UTF8.self)
        #expect(!encoded.contains("Frozen prompt"))
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
