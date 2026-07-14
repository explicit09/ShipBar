import Foundation
import SwiftData

/// Answers closed bridge commands against the live model store.
/// All status changes go through AgentRunLifecycle so invalid
/// transitions are refused exactly like they are in the UI.
@MainActor
struct ShipBarBridgeProcessor {
    let store: ShipBarBridgeStore
    let modelContainer: ModelContainer
    var contextOverride: ModelContext?

    init(store: ShipBarBridgeStore, modelContainer: ModelContainer, contextOverride: ModelContext? = nil) {
        self.store = store
        self.modelContainer = modelContainer
        self.contextOverride = contextOverride
    }

    /// Processes every pending request that does not already have a
    /// response. Returns how many requests were processed.
    @discardableResult
    func processPending() throws -> Int {
        var processed = 0
        for request in try self.store.pendingRequests() {
            if try self.store.response(for: request.id) == nil {
                let response = self.process(request)
                try self.store.writeResponse(response)
                processed += 1
            }
            try self.store.removeRequest(id: request.id)
        }
        return processed
    }

    func process(_ request: ShipBarBridgeRequest) -> ShipBarBridgeResponse {
        let context = self.contextOverride ?? ModelContext(self.modelContainer)
        switch request.command {
        case .listPrepared:
            return self.listPrepared(request: request, context: context)
        case .getContext(let runID):
            return self.getContext(request: request, runID: runID, context: context)
        case .claim(let runID):
            return self.claim(request: request, runID: runID, context: context)
        case .markRunning(let runID):
            return self.mutate(request: request, runID: runID, context: context) { run in
                guard AgentRunLifecycle.transition(run, to: .running) else {
                    return "Run \(runID) is \(run.status.displayLabel) and cannot start running."
                }
                return nil
            }
        case let .requestReview(runID, summary, evidencePaths):
            return self.requestReview(
                request: request,
                runID: runID,
                summary: summary,
                evidencePaths: evidencePaths,
                context: context)
        case let .markFailed(runID, message):
            return self.mutate(request: request, runID: runID, context: context) { run in
                guard AgentRunLifecycle.fail(run, message: message) else {
                    return "Run \(runID) is \(run.status.displayLabel) and cannot be marked failed."
                }
                return nil
            }
        case let .cancel(runID, message):
            return self.mutate(request: request, runID: runID, context: context) { run in
                guard AgentRunLifecycle.transition(run, to: .canceled) else {
                    return "Run \(runID) is \(run.status.displayLabel) and cannot be canceled."
                }
                run.resultSummary = message
                return nil
            }
        case .searchTasks(let query):
            let needle = query.lowercased()
            let matches = self.allTasks(in: context).filter {
                $0.title.lowercased().contains(needle)
                    || $0.taskDescription.lowercased().contains(needle)
            }
            return .success(
                requestID: request.id,
                result: .tasks(matches
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .map(self.summary(for:))))
        case .getToday:
            let today = Calendar.current.startOfDay(for: .now)
            let focused = self.allTasks(in: context)
                .filter { task in
                    guard let focusDate = task.focusDate else { return false }
                    return Calendar.current.isDate(focusDate, inSameDayAs: today)
                }
                .sorted { ($0.focusOrder ?? .max) < ($1.focusOrder ?? .max) }
            return .success(requestID: request.id, result: .tasks(focused.map(self.summary(for:))))
        case .getTask(let taskID):
            guard let task = self.task(id: taskID, in: context) else {
                return .failure(requestID: request.id, message: "Task \(taskID) was not found in ShipBar.")
            }
            return .success(requestID: request.id, result: .tasks([self.summary(for: task)]))
        case .getRunStatus(let runID):
            guard let run = self.run(id: runID, in: context) else {
                return self.missingRun(request: request, runID: runID)
            }
            return .success(requestID: request.id, result: .runStatus(self.summary(for: run)))
        case let .queueCapture(captureID, title, description, projectName, priority, dueAt):
            return self.queueCapture(
                request: request,
                captureID: captureID,
                title: title,
                description: description,
                projectName: projectName,
                priority: priority,
                dueAt: dueAt,
                context: context)
        case let .prepareRun(taskID, repositoryPath, instructions):
            return self.prepareRun(
                request: request,
                taskID: taskID,
                repositoryPath: repositoryPath,
                instructions: instructions,
                context: context)
        }
    }

    private func prepareRun(
        request: ShipBarBridgeRequest,
        taskID: String,
        repositoryPath: String,
        instructions: String,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        guard let task = self.task(id: taskID, in: context) else {
            return .failure(requestID: request.id, message: "Task \(taskID) was not found in ShipBar.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repositoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .failure(requestID: request.id, message: "Repository '\(repositoryPath)' is not a directory.")
        }
        let run = AgentRunLifecycle.prepare(task: task, target: .codex, in: context)
        run.repositoryPathSnapshot = repositoryPath
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanInstructions.isEmpty {
            run.promptSnapshot += "\n\nRemote request:\n\(cleanInstructions)"
        }
        self.save(context)
        return .success(requestID: request.id, result: .runStatus(self.summary(for: run)))
    }

    private func queueCapture(
        request: ShipBarBridgeRequest,
        captureID: String,
        title: String,
        description: String,
        projectName: String?,
        priority: String,
        dueAt: String?,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        if let existing = self.allTasks(in: context).first(where: { $0.sourceCaptureID == captureID }) {
            return .success(requestID: request.id, result: .tasks([self.summary(for: existing)]))
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !captureID.isEmpty, !cleanTitle.isEmpty else {
            return .failure(requestID: request.id, message: "Cloud captures require an ID and title.")
        }
        let taskPriority: TaskPriority = switch priority {
        case "low": .low
        case "high", "urgent": .high
        default: .medium
        }
        let project = projectName.flatMap { requested in
            self.allProjects(in: context).first {
                $0.name.localizedCaseInsensitiveCompare(requested) == .orderedSame
            }
        }
        let dueDate = dueAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let task = ShipTask(
            title: cleanTitle,
            taskDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: taskPriority,
            dueDate: dueDate,
            isInbox: project == nil,
            sourceApp: "ShipBar Relay",
            sourceCaptureID: captureID,
            project: project)
        context.insert(task)
        self.save(context)
        return .success(requestID: request.id, result: .tasks([self.summary(for: task)]))
    }

    private func listPrepared(request: ShipBarBridgeRequest, context: ModelContext) -> ShipBarBridgeResponse {
        let runs = self.allRuns(in: context)
            .filter { $0.status == .prepared && $0.targetRawValue == AgentTarget.codex.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
        return .success(
            requestID: request.id,
            result: .preparedRuns(runs.map(self.summary(for:))))
    }

    private func getContext(
        request: ShipBarBridgeRequest,
        runID: String,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        guard let run = self.run(id: runID, in: context) else {
            return self.missingRun(request: request, runID: runID)
        }
        let task = self.task(id: run.taskID, in: context)
        return .success(
            requestID: request.id,
            result: .runContext(ShipBarBridgeRunContext(
                run: self.summary(for: run),
                prompt: run.promptSnapshot,
                taskDescription: task?.taskDescription ?? "",
                target: run.targetRawValue)))
    }

    private func claim(
        request: ShipBarBridgeRequest,
        runID: String,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        guard let run = self.run(id: runID, in: context) else {
            return self.missingRun(request: request, runID: runID)
        }
        var isDirectory: ObjCBool = false
        let repoExists = FileManager.default.fileExists(
            atPath: run.repositoryPathSnapshot,
            isDirectory: &isDirectory)
        guard !run.repositoryPathSnapshot.isEmpty, repoExists, isDirectory.boolValue else {
            return .failure(
                requestID: request.id,
                message: "Run \(runID) has no usable repository at '\(run.repositoryPathSnapshot)'.")
        }
        guard run.status == .prepared, AgentRunLifecycle.transition(run, to: .handedOff) else {
            return .failure(
                requestID: request.id,
                message: "Run \(runID) is \(run.status.displayLabel) and cannot be claimed.")
        }
        self.save(context)
        return .success(requestID: request.id, result: .acknowledged)
    }

    private func requestReview(
        request: ShipBarBridgeRequest,
        runID: String,
        summary: String,
        evidencePaths: [String],
        context: ModelContext) -> ShipBarBridgeResponse
    {
        guard let run = self.run(id: runID, in: context) else {
            return self.missingRun(request: request, runID: runID)
        }
        guard ShipBarBridgeStore.validateEvidencePaths(
            evidencePaths,
            approvedRoots: [run.repositoryPathSnapshot])
        else {
            return .failure(
                requestID: request.id,
                message: "Evidence paths must live inside the run repository '\(run.repositoryPathSnapshot)'.")
        }
        guard AgentRunLifecycle.transition(run, to: .needsReview) else {
            return .failure(
                requestID: request.id,
                message: "Run \(runID) is \(run.status.displayLabel) and cannot request review.")
        }
        run.resultSummary = summary
        if let evidence = evidencePaths.first {
            run.evidenceURLString = URL(fileURLWithPath: evidence).absoluteString
        }
        self.save(context)
        return .success(requestID: request.id, result: .acknowledged)
    }

    private func mutate(
        request: ShipBarBridgeRequest,
        runID: String,
        context: ModelContext,
        applying change: (AgentRun) -> String?) -> ShipBarBridgeResponse
    {
        guard let run = self.run(id: runID, in: context) else {
            return self.missingRun(request: request, runID: runID)
        }
        if let refusal = change(run) {
            return .failure(requestID: request.id, message: refusal)
        }
        self.save(context)
        return .success(requestID: request.id, result: .acknowledged)
    }

    private func missingRun(request: ShipBarBridgeRequest, runID: String) -> ShipBarBridgeResponse {
        .failure(requestID: request.id, message: "Run \(runID) was not found in ShipBar.")
    }

    private func summary(for run: AgentRun) -> ShipBarBridgeRunSummary {
        ShipBarBridgeRunSummary(
            runID: run.id,
            taskID: run.taskID,
            taskTitle: run.taskTitleSnapshot,
            projectName: run.projectNameSnapshot,
            repositoryPath: run.repositoryPathSnapshot,
            status: run.status.rawValue,
            updatedAt: run.updatedAt)
    }

    private func summary(for task: ShipTask) -> ShipBarBridgeTaskSummary {
        ShipBarBridgeTaskSummary(
            taskID: task.id,
            title: task.title,
            taskDescription: task.taskDescription,
            status: task.status.rawValue,
            priority: task.priority.rawValue,
            type: task.type.rawValue,
            projectName: task.project?.name,
            dueDate: task.dueDate,
            focusDate: task.focusDate,
            focusOrder: task.focusOrder,
            isInbox: task.isInbox,
            updatedAt: task.updatedAt)
    }

    private func allTasks(in context: ModelContext) -> [ShipTask] {
        (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
    }

    private func allRuns(in context: ModelContext) -> [AgentRun] {
        (try? context.fetch(FetchDescriptor<AgentRun>())) ?? []
    }

    private func allProjects(in context: ModelContext) -> [Project] {
        (try? context.fetch(FetchDescriptor<Project>())) ?? []
    }

    private func run(id: String, in context: ModelContext) -> AgentRun? {
        self.allRuns(in: context).first { $0.id == id }
    }

    private func task(id: String, in context: ModelContext) -> ShipTask? {
        self.allTasks(in: context).first { $0.id == id }
    }

    private func save(_ context: ModelContext) {
        ShipBarPersistence.save(context, operation: "Apply bridge command")
    }
}
