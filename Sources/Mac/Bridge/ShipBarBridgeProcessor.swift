import Foundation
import SwiftData

/// Answers closed bridge commands against the live model store.
/// All status changes go through AgentRunLifecycle so invalid
/// transitions are refused exactly like they are in the UI.
@MainActor
struct ShipBarBridgeProcessor {
    typealias PersistenceOperation = (ModelContext, String) -> Bool
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    let store: ShipBarBridgeStore
    let modelContainer: ModelContainer
    var contextOverride: ModelContext?
    let persistenceOperation: PersistenceOperation

    init(
        store: ShipBarBridgeStore,
        modelContainer: ModelContainer,
        contextOverride: ModelContext? = nil,
        persistenceOperation: @escaping PersistenceOperation = { context, operation in
            ShipBarPersistence.save(context, operation: operation)
        })
    {
        self.store = store
        self.modelContainer = modelContainer
        self.contextOverride = contextOverride
        self.persistenceOperation = persistenceOperation
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
        case let .prepareRun(taskID, repositoryPath, instructions, preparationKey):
            return self.prepareRun(
                request: request,
                taskID: taskID,
                repositoryPath: repositoryPath,
                instructions: instructions,
                preparationKey: preparationKey,
                context: context)
        case let .applyProductivity(commandID, command):
            return self.applyProductivity(
                request: request, commandID: commandID, command: command, context: context)
        }
    }

    private func applyProductivity(
        request: ShipBarBridgeRequest,
        commandID: String,
        command: ShipBarProductivityCommand,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        if let task = self.allTasks(in: context).first(where: { $0.lastRemoteCommandID == commandID }) {
            return self.commandSuccess(request, commandID, "Command was already applied.", task: task)
        }
        if let project = self.allProjects(in: context).first(where: { $0.lastRemoteCommandID == commandID }) {
            return self.commandSuccess(request, commandID, "Command was already applied.", project: project)
        }
        switch command.kind {
        case .createTask:
            guard let patch = command.task,
                  let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return .failure(requestID: request.id, message: "createTask requires a title.")
            }
            let task = ShipTask(title: title)
            context.insert(task)
            if let failure = self.apply(patch, to: task, context: context) {
                context.rollback()
                return .failure(requestID: request.id, message: failure)
            }
            task.lastRemoteCommandID = commandID
            task.revision = 1
            task.updatedAt = .now
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(request, commandID, "Created task \(task.title).", task: task)
        case .updateTask:
            guard let task = command.recordID.flatMap({ self.task(id: $0, in: context) }) else {
                return .failure(requestID: request.id, message: "Task was not found.")
            }
            guard self.revisionMatches(command.expectedRevision, task.revision) else {
                return .failure(requestID: request.id, message: "Task revision conflict; refresh before retrying.")
            }
            if let patch = command.task, let failure = self.apply(patch, to: task, context: context) {
                return .failure(requestID: request.id, message: failure)
            }
            self.touch(task, commandID: commandID)
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(request, commandID, "Updated task \(task.title).", task: task)
        case .trashTask, .restoreTask, .permanentlyDeleteTask:
            guard let task = command.recordID.flatMap({ self.task(id: $0, in: context) }) else {
                return .failure(requestID: request.id, message: "Task was not found.")
            }
            guard self.revisionMatches(command.expectedRevision, task.revision) else {
                return .failure(requestID: request.id, message: "Task revision conflict; refresh before retrying.")
            }
            if command.kind == .permanentlyDeleteTask {
                guard task.trashedAt != nil else {
                    return .failure(requestID: request.id, message: "Permanent deletion is allowed only from Trash.")
                }
                ShipBarTaskLifecycle.delete(task, in: context)
                if let failure = self.save(request: request, context: context) { return failure }
                return self.commandSuccess(request, commandID, "Permanently deleted task.")
            }
            task.trashedAt = command.kind == .trashTask ? .now : nil
            self.touch(task, commandID: commandID)
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(
                request, commandID,
                command.kind == .trashTask ? "Moved task to Trash." : "Restored task.", task: task)
        case .createProject:
            guard let patch = command.project,
                  let name = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return .failure(requestID: request.id, message: "createProject requires a name.")
            }
            guard !self.allProjects(in: context).contains(where: {
                $0.trashedAt == nil && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                return .failure(requestID: request.id, message: "An active project named \(name) already exists.")
            }
            let project = Project(name: name)
            context.insert(project)
            self.apply(patch, to: project)
            project.lastRemoteCommandID = commandID
            project.revision = 1
            project.updatedAt = .now
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(request, commandID, "Created project \(project.name).", project: project)
        case .updateProject:
            guard let project = command.recordID.flatMap({ self.project(id: $0, in: context) }) else {
                return .failure(requestID: request.id, message: "Project was not found.")
            }
            guard self.revisionMatches(command.expectedRevision, project.revision) else {
                return .failure(requestID: request.id, message: "Project revision conflict; refresh before retrying.")
            }
            if let patch = command.project { self.apply(patch, to: project) }
            self.touch(project, commandID: commandID)
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(request, commandID, "Updated project \(project.name).", project: project)
        case .trashProject, .restoreProject, .permanentlyDeleteProject:
            guard let project = command.recordID.flatMap({ self.project(id: $0, in: context) }) else {
                return .failure(requestID: request.id, message: "Project was not found.")
            }
            guard self.revisionMatches(command.expectedRevision, project.revision) else {
                return .failure(requestID: request.id, message: "Project revision conflict; refresh before retrying.")
            }
            if command.kind == .permanentlyDeleteProject {
                guard project.trashedAt != nil else {
                    return .failure(requestID: request.id, message: "Permanent deletion is allowed only from Trash.")
                }
                ShipBarProjectLifecycle.delete(project, taskHandling: .deleteTasks, in: context)
                if let failure = self.save(request: request, context: context) { return failure }
                return self.commandSuccess(request, commandID, "Permanently deleted project.")
            }
            if command.kind == .trashProject {
                guard command.taskHandling == "move_tasks_to_inbox" || command.taskHandling == "trash_tasks" else {
                    return .failure(requestID: request.id, message: "Trashing a project requires taskHandling.")
                }
                for task in self.allTasks(in: context).filter({ $0.project?.id == project.id }) {
                    if command.taskHandling == "move_tasks_to_inbox" {
                        task.project = nil; task.isInbox = true
                    } else {
                        task.trashedAt = .now
                    }
                    task.revision += 1; task.updatedAt = .now
                }
                project.trashedAt = .now
            } else {
                project.trashedAt = nil
                for task in self.allTasks(in: context).filter({ $0.project?.id == project.id && $0.trashedAt != nil }) {
                    task.trashedAt = nil; task.revision += 1; task.updatedAt = .now
                }
            }
            self.touch(project, commandID: commandID)
            if let failure = self.save(request: request, context: context) { return failure }
            return self.commandSuccess(
                request, commandID,
                command.kind == .trashProject ? "Moved project to Trash." : "Restored project.", project: project)
        }
    }

    private func revisionMatches(_ expected: Int?, _ actual: Int) -> Bool {
        expected == actual
    }

    private func touch(_ task: ShipTask, commandID: String) {
        task.revision += 1; task.updatedAt = .now; task.lastRemoteCommandID = commandID
    }

    private func touch(_ project: Project, commandID: String) {
        project.revision += 1; project.updatedAt = .now; project.lastRemoteCommandID = commandID
    }

    private func apply(_ patch: ShipBarTaskPatch, to task: ShipTask, context: ModelContext) -> String? {
        if let title = patch.title {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { return "Task title cannot be empty." }
            task.title = clean
        }
        if let value = patch.description { task.taskDescription = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = patch.prompt { task.prompt = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = patch.status, let status = TaskStatus(rawValue: value) { task.status = status } else if patch.status != nil { return "Unsupported task status." }
        if let value = patch.priority, let priority = TaskPriority(rawValue: value) { task.priority = priority } else if patch.priority != nil { return "Unsupported task priority." }
        if let value = patch.type, let type = TaskType(rawValue: value) { task.type = type } else if patch.type != nil { return "Unsupported task type." }
        if patch.clearProject == true { task.project = nil; task.isInbox = true }
        if let projectID = patch.projectID {
            guard let project = self.project(id: projectID, in: context), project.trashedAt == nil else { return "Project was not found." }
            task.project = project; task.isInbox = false
        } else if let projectName = patch.projectName {
            guard let project = self.allProjects(in: context).first(where: { $0.trashedAt == nil && $0.name.localizedCaseInsensitiveCompare(projectName) == .orderedSame }) else { return "Project was not found." }
            task.project = project; task.isInbox = false
        }
        if patch.clearDueDate == true { task.dueDate = nil }
        if let dueAt = patch.dueAt {
            guard let due = ISO8601DateFormatter().date(from: dueAt) else { return "dueAt must be ISO 8601." }
            task.dueDate = due
        }
        if patch.removeFromToday == true { task.focusDate = nil; task.focusOrder = nil }
        if let focusDate = patch.focusDate {
            guard let date = ISO8601DateFormatter().date(from: focusDate) ?? Self.dayFormatter.date(from: focusDate) else { return "focusDate must be YYYY-MM-DD or ISO 8601." }
            task.focusDate = date
        }
        if let order = patch.focusOrder { task.focusOrder = order }
        if let value = patch.sourceApp { task.sourceApp = value }
        if let value = patch.sourceURL { task.sourceURL = value }
        return nil
    }

    private func apply(_ patch: ShipBarProjectPatch, to project: Project) {
        if let value = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { project.name = value }
        if let value = patch.outcome { project.outcome = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = patch.basePrompt { project.basePrompt = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = patch.repoPath { project.repoPath = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = patch.color { project.color = value }
        if let value = patch.icon { project.icon = value }
        if let value = patch.sortOrder { project.sortOrder = value }
    }

    private func commandSuccess(
        _ request: ShipBarBridgeRequest, _ commandID: String, _ summary: String,
        task: ShipTask? = nil, project: Project? = nil) -> ShipBarBridgeResponse
    {
        .success(requestID: request.id, result: .commandResult(ShipBarBridgeCommandResult(
            commandID: commandID, status: "applied", summary: summary,
            task: task.map(self.summary(for:)), project: project.map(self.summary(for:)))))
    }

    private func prepareRun(
        request: ShipBarBridgeRequest,
        taskID: String,
        repositoryPath: String,
        instructions: String,
        preparationKey: String?,
        context: ModelContext) -> ShipBarBridgeResponse
    {
        if let preparationKey,
           !preparationKey.isEmpty,
           let existing = self.allRuns(in: context).first(where: { $0.preparationKey == preparationKey })
        {
            return .success(requestID: request.id, result: .runStatus(self.summary(for: existing)))
        }
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
        run.preparationKey = preparationKey ?? ""
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanInstructions.isEmpty {
            run.promptSnapshot += "\n\nRemote request:\n\(cleanInstructions)"
        }
        if let failure = self.save(request: request, context: context) { return failure }
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
        if let failure = self.save(request: request, context: context) { return failure }
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
        if let failure = self.save(request: request, context: context) { return failure }
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
        if let failure = self.save(request: request, context: context) { return failure }
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
        if let failure = self.save(request: request, context: context) { return failure }
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
            prompt: task.prompt,
            status: task.status.rawValue,
            priority: task.priority.rawValue,
            type: task.type.rawValue,
            projectName: task.project?.name,
            dueDate: task.dueDate,
            focusDate: task.focusDate,
            focusOrder: task.focusOrder,
            isInbox: task.isInbox,
            updatedAt: task.updatedAt,
            revision: task.revision,
            trashedAt: task.trashedAt)
    }

    private func summary(for project: Project) -> ShipBarBridgeProjectSummary {
        ShipBarBridgeProjectSummary(
            projectID: project.id, name: project.name, outcome: project.outcome,
            basePrompt: project.basePrompt, repoPath: project.repoPath,
            color: project.color, icon: project.icon, sortOrder: project.sortOrder,
            updatedAt: project.updatedAt, revision: project.revision, trashedAt: project.trashedAt)
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

    private func project(id: String, in context: ModelContext) -> Project? {
        self.allProjects(in: context).first { $0.id == id }
    }

    private func save(
        request: ShipBarBridgeRequest,
        context: ModelContext) -> ShipBarBridgeResponse?
    {
        guard self.persistenceOperation(context, "Apply bridge command") else {
            context.rollback()
            return .failure(
                requestID: request.id,
                message: "ShipBar could not save this bridge command. No changes were committed; retry after checking local storage.")
        }
        return nil
    }
}
