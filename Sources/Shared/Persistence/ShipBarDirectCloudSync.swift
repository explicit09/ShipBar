import CloudKit
import Foundation
import SwiftData

struct ShipBarSyncResult: Equatable, Sendable {
    let pulledRecords: Int
    let pushedRecords: Int
}

enum ShipBarDirectCloudSync {
    private static let taskRecordType = "ShipBarDirectTask"
    private static let projectRecordType = "ShipBarDirectProject"
    private static let agentRunRecordType = "ShipBarDirectAgentRun"
    private static let tombstoneRecordType = "ShipBarDirectTombstone"
    private static let manifestRecordType = "ShipBarDirectManifest"
    private static let manifestRecordName = "current"

    struct ManifestIDs: Equatable, Sendable {
        var projectIDs: [String]
        var taskIDs: [String]
        var runIDs: [String]
        var tombstoneIDs: [String]

        init(
            projectIDs: [String] = [],
            taskIDs: [String] = [],
            runIDs: [String] = [],
            tombstoneIDs: [String] = [])
        {
            self.projectIDs = projectIDs
            self.taskIDs = taskIDs
            self.runIDs = runIDs
            self.tombstoneIDs = tombstoneIDs
        }
    }

    static func mergeManifest(remote: ManifestIDs, local: ManifestIDs) -> ManifestIDs {
        func union(_ lhs: [String], _ rhs: [String]) -> [String] {
            Array(Set(lhs).union(rhs)).sorted()
        }
        return ManifestIDs(
            projectIDs: union(remote.projectIDs, local.projectIDs),
            taskIDs: union(remote.taskIDs, local.taskIDs),
            runIDs: union(remote.runIDs, local.runIDs),
            tombstoneIDs: union(remote.tombstoneIDs, local.tombstoneIDs))
    }

    struct ProjectPayload: Sendable {
        let id: String
        let name: String
        let outcome: String
        let basePrompt: String
        let repoPath: String
        let color: String
        let icon: String
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date

        init(
            id: String,
            name: String,
            outcome: String = "",
            basePrompt: String,
            repoPath: String,
            color: String,
            icon: String,
            sortOrder: Int,
            createdAt: Date,
            updatedAt: Date)
        {
            self.id = id
            self.name = name
            self.outcome = outcome
            self.basePrompt = basePrompt
            self.repoPath = repoPath
            self.color = color
            self.icon = icon
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    struct TaskPayload: Sendable {
        let id: String
        let title: String
        let taskDescription: String
        let prompt: String
        let status: String
        let priority: String
        let type: String
        let createdAt: Date
        let updatedAt: Date
        let completedAt: Date?
        let dueDate: Date?
        let focusDate: Date?
        let focusOrder: Int?
        let isInbox: Bool
        let sourceApp: String
        let sourceURL: String
        let rawCaptureText: String
        let sourceCaptureID: String
        let projectID: String?
        let projectName: String?

        init(
            id: String,
            title: String,
            taskDescription: String,
            prompt: String,
            status: String,
            priority: String,
            type: String,
            createdAt: Date,
            updatedAt: Date,
            completedAt: Date?,
            dueDate: Date?,
            focusDate: Date? = nil,
            focusOrder: Int? = nil,
            isInbox: Bool,
            sourceApp: String,
            sourceURL: String,
            rawCaptureText: String,
            sourceCaptureID: String = "",
            projectID: String?,
            projectName: String?)
        {
            self.id = id
            self.title = title
            self.taskDescription = taskDescription
            self.prompt = prompt
            self.status = status
            self.priority = priority
            self.type = type
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
            self.dueDate = dueDate
            self.focusDate = focusDate
            self.focusOrder = focusOrder
            self.isInbox = isInbox
            self.sourceApp = sourceApp
            self.sourceURL = sourceURL
            self.rawCaptureText = rawCaptureText
            self.sourceCaptureID = sourceCaptureID
            self.projectID = projectID
            self.projectName = projectName
        }
    }

    struct AgentRunPayload: Sendable {
        let id: String
        let taskID: String
        let projectID: String?
        let taskTitleSnapshot: String
        let projectNameSnapshot: String?
        let targetRawValue: String
        let statusRawValue: String
        let promptSnapshot: String
        let repositoryPathSnapshot: String
        let createdAt: Date
        let updatedAt: Date
        let startedAt: Date?
        let finishedAt: Date?
        let resultSummary: String
        let evidenceURLString: String
        let errorMessage: String
        let preparationKey: String
    }

    struct TombstonePayload: Sendable {
        let recordKind: String
        let recordID: String
        let taskHandling: String?
        let deletedAt: Date

        var cloudRecordName: String {
            ShipBarDeletionTombstone.cloudRecordName(kind: self.recordKind, id: self.recordID)
        }
    }

    private struct LocalPayloads: Sendable {
        let projects: [ProjectPayload]
        let tasks: [TaskPayload]
        let runs: [AgentRunPayload]
        let tombstones: [TombstonePayload]
    }

    static func syncOnce(modelContainer: ModelContainer) async throws -> ShipBarSyncResult {
        let database = CKContainer(identifier: ShipBarModelContainer.cloudKitIdentifier).privateCloudDatabase

        Self.writeDiagnostic("sync start")
        let manifest = try await Self.fetchManifest(from: database)
        let remoteProjects = try await Self.fetchRecords(ids: manifest.projectIDs, from: database)
        let remoteTasks = try await Self.fetchRecords(ids: manifest.taskIDs, from: database)
        let remoteRuns = try await Self.fetchRecords(ids: manifest.runIDs, from: database)
        let remoteTombstones = try await Self.fetchRecords(ids: manifest.tombstoneIDs, from: database)
        Self.writeDiagnostic("sync fetched remoteProjects=\(remoteProjects.count) remoteTasks=\(remoteTasks.count) runs=\(remoteRuns.count) tombstones=\(remoteTombstones.count)")
        await MainActor.run {
            Self.apply(
                remoteProjects: remoteProjects,
                remoteTasks: remoteTasks,
                remoteRuns: remoteRuns,
                remoteTombstones: remoteTombstones,
                to: modelContainer)
        }

        let localPayloads = await MainActor.run {
            Self.localPayloads(from: modelContainer)
        }
        Self.writeDiagnostic("sync push localProjects=\(localPayloads.projects.count) localTasks=\(localPayloads.tasks.count) runs=\(localPayloads.runs.count) tombstones=\(localPayloads.tombstones.count)")
        let pushedRecords = try await Self.push(
            projects: localPayloads.projects,
            tasks: localPayloads.tasks,
            runs: localPayloads.runs,
            tombstones: localPayloads.tombstones,
            to: database)
        return ShipBarSyncResult(
            pulledRecords: remoteProjects.count + remoteTasks.count + remoteRuns.count + remoteTombstones.count,
            pushedRecords: pushedRecords)
    }

    static func isMissingRecordError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem
    }

    @MainActor
    private static func localPayloads(from modelContainer: ModelContainer) -> LocalPayloads {
        let context = ModelContext(modelContainer)
        let cleanup = ShipBarLocalDuplicateResolver.cleanup(in: context)
        if cleanup.didChange {
            ShipBarPersistence.save(context, operation: "Preflight sync cleanup", notifiesSync: false)
            Self.writeDiagnostic("preflight cleanup updatedProjects=\(cleanup.updatedProjects) deletedProjects=\(cleanup.deletedProjects) deletedTasks=\(cleanup.deletedTasks)")
        }

        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).map {
            ProjectPayload(
                id: $0.id,
                name: $0.name,
                outcome: $0.outcome,
                basePrompt: $0.basePrompt,
                repoPath: $0.repoPath,
                color: $0.color,
                icon: $0.icon,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt)
        }
        let tasks = ((try? context.fetch(FetchDescriptor<ShipTask>())) ?? []).map {
            TaskPayload(
                id: $0.id,
                title: $0.title,
                taskDescription: $0.taskDescription,
                prompt: $0.prompt,
                status: $0.status.rawValue,
                priority: $0.priority.rawValue,
                type: $0.type.rawValue,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                completedAt: $0.completedAt,
                dueDate: $0.dueDate,
                focusDate: $0.focusDate,
                focusOrder: $0.focusOrder,
                isInbox: $0.isInbox,
                sourceApp: $0.sourceApp,
                sourceURL: $0.sourceURL,
                rawCaptureText: $0.rawCaptureText,
                sourceCaptureID: $0.sourceCaptureID,
                projectID: $0.project?.id,
                projectName: $0.project?.name)
        }
        let runs = ((try? context.fetch(FetchDescriptor<AgentRun>())) ?? []).map {
            AgentRunPayload(
                id: $0.id,
                taskID: $0.taskID,
                projectID: $0.projectID,
                taskTitleSnapshot: $0.taskTitleSnapshot,
                projectNameSnapshot: $0.projectNameSnapshot,
                targetRawValue: $0.targetRawValue,
                statusRawValue: $0.statusRawValue,
                promptSnapshot: $0.promptSnapshot,
                repositoryPathSnapshot: $0.repositoryPathSnapshot,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                startedAt: $0.startedAt,
                finishedAt: $0.finishedAt,
                resultSummary: $0.resultSummary,
                evidenceURLString: $0.evidenceURLString,
                errorMessage: $0.errorMessage,
                preparationKey: $0.preparationKey)
        }
        let tombstones = ShipBarDeletionLog.tombstones(in: context).map {
            TombstonePayload(
                recordKind: $0.recordKind,
                recordID: $0.recordID,
                taskHandling: $0.taskHandling,
                deletedAt: $0.deletedAt)
        }
        return LocalPayloads(projects: projects, tasks: tasks, runs: runs, tombstones: tombstones)
    }

    private static func push(
        projects: [ProjectPayload],
        tasks: [TaskPayload],
        runs: [AgentRunPayload],
        tombstones: [TombstonePayload],
        to database: CKDatabase) async throws -> Int
    {
        let deletedProjectIDs = Set(tombstones.filter { $0.recordKind == ShipBarDeletionKind.project.rawValue }.map(\.recordID))
        let deletedTaskIDs = Set(tombstones.filter { $0.recordKind == ShipBarDeletionKind.task.rawValue }.map(\.recordID))
        let liveProjects = projects.filter { !deletedProjectIDs.contains($0.id) }
        let liveTasks = tasks.filter { !deletedTaskIDs.contains($0.id) && !deletedProjectIDs.contains($0.projectID ?? "") }

        let projectRecords = liveProjects.map { project in
            let record = CKRecord(recordType: Self.projectRecordType, recordID: CKRecord.ID(recordName: project.id))
            record["name"] = project.name
            record["outcome"] = project.outcome
            record["basePrompt"] = project.basePrompt
            record["repoPath"] = project.repoPath
            record["color"] = project.color
            record["icon"] = project.icon
            record["sortOrder"] = project.sortOrder
            record["createdAt"] = project.createdAt
            record["updatedAt"] = project.updatedAt
            return record
        }
        let taskRecords = liveTasks.map { task in
            let record = CKRecord(recordType: Self.taskRecordType, recordID: CKRecord.ID(recordName: task.id))
            record["title"] = task.title
            record["taskDescription"] = task.taskDescription
            record["prompt"] = task.prompt
            record["status"] = task.status
            record["priority"] = task.priority
            record["type"] = task.type
            record["createdAt"] = task.createdAt
            record["updatedAt"] = task.updatedAt
            record["completedAt"] = task.completedAt
            record["dueDate"] = task.dueDate
            record["focusDate"] = task.focusDate
            record["focusOrder"] = task.focusOrder
            record["isInbox"] = task.isInbox
            record["sourceApp"] = task.sourceApp
            record["sourceURL"] = task.sourceURL
            record["rawCaptureText"] = task.rawCaptureText
            record["sourceCaptureID"] = task.sourceCaptureID
            record["projectID"] = task.projectID
            record["projectName"] = task.projectName
            return record
        }
        let runRecords = runs.map { run in
            let record = CKRecord(recordType: Self.agentRunRecordType, recordID: CKRecord.ID(recordName: run.id))
            record["taskID"] = run.taskID
            record["projectID"] = run.projectID
            record["taskTitleSnapshot"] = run.taskTitleSnapshot
            record["projectNameSnapshot"] = run.projectNameSnapshot
            record["targetRawValue"] = run.targetRawValue
            record["statusRawValue"] = run.statusRawValue
            record["promptSnapshot"] = run.promptSnapshot
            record["repositoryPathSnapshot"] = run.repositoryPathSnapshot
            record["createdAt"] = run.createdAt
            record["updatedAt"] = run.updatedAt
            record["startedAt"] = run.startedAt
            record["finishedAt"] = run.finishedAt
            record["resultSummary"] = run.resultSummary
            record["evidenceURLString"] = run.evidenceURLString
            record["errorMessage"] = run.errorMessage
            record["preparationKey"] = run.preparationKey
            return record
        }
        let tombstoneRecords = tombstones.map { tombstone in
            let record = CKRecord(
                recordType: Self.tombstoneRecordType,
                recordID: CKRecord.ID(recordName: tombstone.cloudRecordName))
            record["recordKind"] = tombstone.recordKind
            record["recordIDValue"] = tombstone.recordID
            record["taskHandling"] = tombstone.taskHandling
            record["deletedAt"] = tombstone.deletedAt
            return record
        }

        let recordsToSave = projectRecords + taskRecords + runRecords + tombstoneRecords
        do {
            let recordsToDelete = tombstones.compactMap(Self.deletedRecordID(for:))
            try await Self.modifyRecords(
                saving: recordsToSave,
                deleting: [],
                in: database,
                savePolicy: .allKeys)
            try await Self.updateManifest(
                local: ManifestIDs(
                    projectIDs: liveProjects.map(\.id),
                    taskIDs: liveTasks.map(\.id),
                    runIDs: runs.map(\.id),
                    tombstoneIDs: tombstones.map(\.cloudRecordName)),
                deletingProjectIDs: deletedProjectIDs,
                deletingTaskIDs: deletedTaskIDs,
                in: database)
            Self.writeDiagnostic("push saved projects=\(projectRecords.count) tasks=\(taskRecords.count) runs=\(runRecords.count) tombstones=\(tombstoneRecords.count)")
            await Self.deleteObsoleteRecords(recordsToDelete, from: database)
        } catch {
            Self.writeDiagnostic("push failed: \(error)")
            throw error
        }
        return recordsToSave.count + 1
    }

    private static func updateManifest(
        local: ManifestIDs,
        deletingProjectIDs: Set<String>,
        deletingTaskIDs: Set<String>,
        in database: CKDatabase) async throws
    {
        for attempt in 1...6 {
            let existing = try await Self.fetchManifestRecord(from: database)
            let remote = existing.map(Self.manifestIDs(from:)) ?? ManifestIDs()
            var merged = Self.mergeManifest(remote: remote, local: local)
            merged.projectIDs.removeAll { deletingProjectIDs.contains($0) }
            merged.taskIDs.removeAll { deletingTaskIDs.contains($0) }
            let manifest = existing ?? CKRecord(
                recordType: Self.manifestRecordType,
                recordID: CKRecord.ID(recordName: Self.manifestRecordName))
            Self.setStringList(merged.projectIDs, for: "projectIDs", on: manifest)
            Self.setStringList(merged.taskIDs, for: "taskIDs", on: manifest)
            Self.setStringList(merged.runIDs, for: "runIDs", on: manifest)
            Self.setStringList(merged.tombstoneIDs, for: "tombstoneIDs", on: manifest)
            do {
                try await Self.modifyRecords(
                    saving: [manifest], deleting: [], in: database,
                    savePolicy: .ifServerRecordUnchanged)
                return
            } catch where Self.isConflictError(error) && attempt < 6 {
                Self.writeDiagnostic("manifest conflict; refetching attempt=\(attempt)")
            }
        }
        throw NSError(
            domain: "ShipBarDirectCloudSync", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Cloud manifest remained conflicted after retrying."])
    }

    private static func isConflictError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == .serverRecordChanged { return true }
        guard cloudError.code == .partialFailure,
              let partial = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]
        else { return false }
        return partial.values.contains { ($0 as? CKError)?.code == .serverRecordChanged }
    }

    private static func setStringList(_ values: [String], for key: String, on record: CKRecord) {
        if values.isEmpty {
            record[key] = nil
        } else {
            record[key] = values as NSArray
        }
    }

    private static func deleteObsoleteRecords(_ recordIDs: [CKRecord.ID], from database: CKDatabase) async {
        guard !recordIDs.isEmpty else { return }
        do {
            try await Self.modifyRecords(
                saving: [],
                deleting: recordIDs,
                in: database,
                savePolicy: .allKeys)
            Self.writeDiagnostic("deleted obsolete records=\(recordIDs.count)")
        } catch {
            Self.writeDiagnostic("obsolete record delete skipped count=\(recordIDs.count): \(error)")
        }
    }

    private static func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        in database: CKDatabase,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy)
        async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: recordIDsToDelete)
            operation.savePolicy = savePolicy
            let errorLock = NSLock()
            var recordErrors: [Error] = []
            operation.perRecordSaveBlock = { recordID, saveResult in
                switch saveResult {
                case .success(let record) where recordID.recordName == Self.manifestRecordName:
                    let projectIDs = record["projectIDs"] as? [String] ?? []
                    let taskIDs = record["taskIDs"] as? [String] ?? []
                    let runIDs = record["runIDs"] as? [String] ?? []
                    let tombstoneIDs = record["tombstoneIDs"] as? [String] ?? []
                    Self.writeDiagnostic("manifest save callback projects=\(projectIDs.count) tasks=\(taskIDs.count) runs=\(runIDs.count) tombstones=\(tombstoneIDs.count)")
                case .success:
                    break
                case .failure(let error):
                    let message = "record save failed id=\(recordID.recordName): \(error)"
                    Self.writeDiagnostic(message)
                    errorLock.lock()
                    recordErrors.append(error)
                    errorLock.unlock()
                }
            }
            operation.modifyRecordsResultBlock = { result in
                errorLock.lock()
                let errors = recordErrors
                errorLock.unlock()
                guard errors.isEmpty else {
                    continuation.resume(throwing: errors[0])
                    return
                }
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private static func deletedRecordID(for tombstone: TombstonePayload) -> CKRecord.ID? {
        switch tombstone.recordKind {
        case ShipBarDeletionKind.project.rawValue:
            CKRecord.ID(recordName: tombstone.recordID)
        case ShipBarDeletionKind.task.rawValue:
            CKRecord.ID(recordName: tombstone.recordID)
        default:
            nil
        }
    }

    private static func fetchManifest(from database: CKDatabase) async throws -> (
        projectIDs: [String],
        taskIDs: [String],
        runIDs: [String],
        tombstoneIDs: [String])
    {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.manifestRecordName))
            let projectIDs = record["projectIDs"] as? [String] ?? []
            let taskIDs = record["taskIDs"] as? [String] ?? []
            let runIDs = record["runIDs"] as? [String] ?? []
            let tombstoneIDs = record["tombstoneIDs"] as? [String] ?? []
            Self.writeDiagnostic("manifest fetched projects=\(projectIDs.count) tasks=\(taskIDs.count) runs=\(runIDs.count) tombstones=\(tombstoneIDs.count)")
            return (projectIDs, taskIDs, runIDs, tombstoneIDs)
        } catch where Self.isMissingRecordError(error) {
            Self.writeDiagnostic("manifest missing; treating as first sync")
            return ([], [], [], [])
        } catch {
            Self.writeDiagnostic("manifest fetch failed: \(error)")
            throw error
        }
    }

    private static func fetchManifestRecord(from database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: Self.manifestRecordName))
        } catch where Self.isMissingRecordError(error) {
            return nil
        }
    }

    private static func manifestIDs(from record: CKRecord) -> ManifestIDs {
        ManifestIDs(
            projectIDs: record["projectIDs"] as? [String] ?? [],
            taskIDs: record["taskIDs"] as? [String] ?? [],
            runIDs: record["runIDs"] as? [String] ?? [],
            tombstoneIDs: record["tombstoneIDs"] as? [String] ?? [])
    }

    private static func fetchRecords(ids: [String], from database: CKDatabase) async throws -> [CKRecord] {
        guard !ids.isEmpty else { return [] }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
        let results: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            results = try await database.records(for: recordIDs)
        } catch {
            Self.writeDiagnostic("record fetch failed count=\(ids.count): \(error)")
            throw error
        }
        var records: [CKRecord] = []
        for (id, result) in results {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error) where Self.isMissingRecordError(error):
                Self.writeDiagnostic("record missing id=\(id.recordName); skipping stale manifest entry")
            case .failure(let error):
                Self.writeDiagnostic("record fetch failed id=\(id.recordName): \(error)")
                throw error
            }
        }
        return records
    }

    @MainActor
    static func applyPayload(
        projects remoteProjects: [ProjectPayload],
        tasks remoteTasks: [TaskPayload],
        runs remoteRuns: [AgentRunPayload] = [],
        tombstones remoteTombstones: [TombstonePayload],
        to modelContainer: ModelContainer)
    {
        let context = ModelContext(modelContainer)
        let localProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let localTasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        let localRuns = (try? context.fetch(FetchDescriptor<AgentRun>())) ?? []
        var projectsByID = Self.newestValuesByID(localProjects, id: \.id, updatedAt: \.updatedAt)
        var tasksByID = Self.newestValuesByID(localTasks, id: \.id, updatedAt: \.updatedAt)
        var runsByID = Self.newestValuesByID(localRuns, id: \.id, updatedAt: \.updatedAt)

        for tombstone in remoteTombstones {
            guard let kind = ShipBarDeletionKind(rawValue: tombstone.recordKind) else { continue }
            ShipBarDeletionLog.record(
                kind,
                id: tombstone.recordID,
                taskHandling: tombstone.taskHandling,
                deletedAt: tombstone.deletedAt,
                in: context)
            switch kind {
            case .project:
                if let project = projectsByID[tombstone.recordID] {
                    let taskHandling = ShipBarProjectTaskHandling(rawValue: tombstone.taskHandling ?? "")
                        ?? .deleteTasks
                    ShipBarProjectLifecycle.delete(project, taskHandling: taskHandling, deletedAt: tombstone.deletedAt, in: context)
                    projectsByID.removeValue(forKey: tombstone.recordID)
                    tasksByID = Self.newestValuesByID(
                        (try? context.fetch(FetchDescriptor<ShipTask>())) ?? [],
                        id: \.id,
                        updatedAt: \.updatedAt)
                }
            case .task:
                if let task = tasksByID[tombstone.recordID] {
                    context.delete(task)
                    tasksByID.removeValue(forKey: tombstone.recordID)
                }
            }
        }

        let newestProjectTombstones = Self.newestValuesByID(
            remoteTombstones.filter { $0.recordKind == ShipBarDeletionKind.project.rawValue },
            id: \.recordID,
            updatedAt: \.deletedAt)
        let deletedProjectHandling = newestProjectTombstones.mapValues {
            ShipBarProjectTaskHandling(rawValue: $0.taskHandling ?? "") ?? .deleteTasks
        }
        let deletedProjectIDs = Set(deletedProjectHandling.keys)
        let deletedTaskIDs = Set(remoteTombstones.filter { $0.recordKind == ShipBarDeletionKind.task.rawValue }.map(\.recordID))

        for payload in remoteProjects where !deletedProjectIDs.contains(payload.id) {
            if let project = projectsByID[payload.id] {
                guard payload.updatedAt >= project.updatedAt else { continue }
                Self.update(project, with: payload)
            } else {
                let project = Self.makeProject(from: payload, fallbackSortOrder: localProjects.count)
                context.insert(project)
                projectsByID[project.id] = project
            }
        }

        for payload in remoteTasks where !deletedTaskIDs.contains(payload.id) {
            let deletedProjectTaskHandling = payload.projectID.flatMap { deletedProjectHandling[$0] }
            guard deletedProjectTaskHandling != .deleteTasks else { continue }

            let project = payload.projectID.flatMap { projectsByID[$0] }
            if let task = tasksByID[payload.id] {
                guard payload.updatedAt >= task.updatedAt else { continue }
                Self.update(
                    task,
                    with: payload,
                    project: project,
                    forceInbox: deletedProjectTaskHandling == .moveToInbox)
            } else {
                let task = Self.makeTask(
                    from: payload,
                    project: project,
                    forceInbox: deletedProjectTaskHandling == .moveToInbox)
                context.insert(task)
                tasksByID[task.id] = task
            }
        }

        for payload in remoteRuns {
            if let run = runsByID[payload.id] {
                guard payload.updatedAt >= run.updatedAt else { continue }
                Self.update(run, with: payload)
            } else {
                let run = Self.makeAgentRun(from: payload)
                context.insert(run)
                runsByID[run.id] = run
            }
        }

        let cleanup = ShipBarLocalDuplicateResolver.cleanup(in: context)
        ShipBarPersistence.save(context, operation: "Apply direct CloudKit payload", notifiesSync: false)
        let finalTasks = (try? context.fetchCount(FetchDescriptor<ShipTask>())) ?? -1
        Self.writeDiagnostic("apply complete localTasks=\(finalTasks) updatedProjects=\(cleanup.updatedProjects) deletedProjects=\(cleanup.deletedProjects) deletedTasks=\(cleanup.deletedTasks)")
    }

    static func newestValuesByID<Value>(
        _ values: [Value],
        id: KeyPath<Value, String>,
        updatedAt: KeyPath<Value, Date>) -> [String: Value]
    {
        values.reduce(into: [:]) { result, value in
            let valueID = value[keyPath: id]
            guard let existing = result[valueID] else {
                result[valueID] = value
                return
            }
            if value[keyPath: updatedAt] >= existing[keyPath: updatedAt] {
                result[valueID] = value
            }
        }
    }

    @MainActor
    private static func apply(
        remoteProjects: [CKRecord],
        remoteTasks: [CKRecord],
        remoteRuns: [CKRecord],
        remoteTombstones: [CKRecord],
        to modelContainer: ModelContainer)
    {
        Self.applyPayload(
            projects: remoteProjects.map(Self.projectPayload(from:)),
            tasks: remoteTasks.map(Self.taskPayload(from:)),
            runs: remoteRuns.map(Self.agentRunPayload(from:)),
            tombstones: remoteTombstones.map(Self.tombstonePayload(from:)),
            to: modelContainer)
    }

    private static func makeProject(from payload: ProjectPayload, fallbackSortOrder: Int) -> Project {
        Project(
            id: payload.id,
            name: payload.name,
            outcome: payload.outcome,
            basePrompt: payload.basePrompt,
            repoPath: payload.repoPath,
            color: payload.color,
            icon: payload.icon,
            sortOrder: payload.sortOrder,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt)
    }

    private static func update(_ project: Project, with payload: ProjectPayload) {
        project.name = payload.name
        project.outcome = payload.outcome
        project.basePrompt = payload.basePrompt
        project.repoPath = payload.repoPath
        project.color = payload.color
        project.icon = payload.icon
        project.sortOrder = payload.sortOrder
        project.createdAt = payload.createdAt
        project.updatedAt = payload.updatedAt
    }

    private static func makeTask(from payload: TaskPayload, project: Project?, forceInbox: Bool = false) -> ShipTask {
        ShipTask(
            id: payload.id,
            title: payload.title,
            taskDescription: payload.taskDescription,
            prompt: payload.prompt,
            status: TaskStatus(rawValue: payload.status) ?? .todo,
            priority: TaskPriority(rawValue: payload.priority) ?? .medium,
            type: TaskType(rawValue: payload.type) ?? .idea,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            completedAt: payload.completedAt,
            dueDate: payload.dueDate,
            isInbox: forceInbox ? true : payload.isInbox,
            sourceApp: payload.sourceApp,
            sourceURL: payload.sourceURL,
            rawCaptureText: payload.rawCaptureText,
            sourceCaptureID: payload.sourceCaptureID,
            focusDate: payload.focusDate,
            focusOrder: payload.focusOrder,
            project: forceInbox ? nil : project)
    }

    private static func update(_ task: ShipTask, with payload: TaskPayload, project: Project?, forceInbox: Bool = false) {
        task.title = payload.title
        task.taskDescription = payload.taskDescription
        task.prompt = payload.prompt
        task.status = TaskStatus(rawValue: payload.status) ?? .todo
        task.priority = TaskPriority(rawValue: payload.priority) ?? .medium
        task.type = TaskType(rawValue: payload.type) ?? .idea
        task.createdAt = payload.createdAt
        task.updatedAt = payload.updatedAt
        task.completedAt = payload.completedAt
        task.dueDate = payload.dueDate
        task.focusDate = payload.focusDate
        task.focusOrder = payload.focusOrder
        task.isInbox = forceInbox ? true : payload.isInbox
        task.sourceApp = payload.sourceApp
        task.sourceURL = payload.sourceURL
        task.rawCaptureText = payload.rawCaptureText
        task.sourceCaptureID = payload.sourceCaptureID
        task.project = forceInbox ? nil : project
    }

    private static func makeAgentRun(from payload: AgentRunPayload) -> AgentRun {
        AgentRun(
            id: payload.id,
            taskID: payload.taskID,
            projectID: payload.projectID,
            taskTitleSnapshot: payload.taskTitleSnapshot,
            projectNameSnapshot: payload.projectNameSnapshot,
            targetRawValue: payload.targetRawValue,
            statusRawValue: payload.statusRawValue,
            promptSnapshot: payload.promptSnapshot,
            repositoryPathSnapshot: payload.repositoryPathSnapshot,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            startedAt: payload.startedAt,
            finishedAt: payload.finishedAt,
            resultSummary: payload.resultSummary,
            evidenceURLString: payload.evidenceURLString,
            errorMessage: payload.errorMessage,
            preparationKey: payload.preparationKey)
    }

    private static func update(_ run: AgentRun, with payload: AgentRunPayload) {
        run.taskID = payload.taskID
        run.projectID = payload.projectID
        run.taskTitleSnapshot = payload.taskTitleSnapshot
        run.projectNameSnapshot = payload.projectNameSnapshot
        run.targetRawValue = payload.targetRawValue
        run.statusRawValue = payload.statusRawValue
        run.promptSnapshot = payload.promptSnapshot
        run.repositoryPathSnapshot = payload.repositoryPathSnapshot
        run.createdAt = payload.createdAt
        run.updatedAt = payload.updatedAt
        run.startedAt = payload.startedAt
        run.finishedAt = payload.finishedAt
        run.resultSummary = payload.resultSummary
        run.evidenceURLString = payload.evidenceURLString
        run.errorMessage = payload.errorMessage
        run.preparationKey = payload.preparationKey
    }

    private static func projectPayload(from record: CKRecord) -> ProjectPayload {
        ProjectPayload(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "Project",
            outcome: record["outcome"] as? String ?? "",
            basePrompt: record["basePrompt"] as? String ?? "",
            repoPath: record["repoPath"] as? String ?? "",
            color: record["color"] as? String ?? "blue",
            icon: record["icon"] as? String ?? "square.stack.3d.up",
            sortOrder: record["sortOrder"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? .now,
            updatedAt: record["updatedAt"] as? Date ?? .now)
    }

    private static func taskPayload(from record: CKRecord) -> TaskPayload {
        TaskPayload(
            id: record.recordID.recordName,
            title: record["title"] as? String ?? "Untitled",
            taskDescription: record["taskDescription"] as? String ?? "",
            prompt: record["prompt"] as? String ?? "",
            status: record["status"] as? String ?? TaskStatus.todo.rawValue,
            priority: record["priority"] as? String ?? TaskPriority.medium.rawValue,
            type: record["type"] as? String ?? TaskType.idea.rawValue,
            createdAt: record["createdAt"] as? Date ?? .now,
            updatedAt: record["updatedAt"] as? Date ?? .now,
            completedAt: record["completedAt"] as? Date,
            dueDate: record["dueDate"] as? Date,
            focusDate: record["focusDate"] as? Date,
            focusOrder: record["focusOrder"] as? Int,
            isInbox: record["isInbox"] as? Bool ?? true,
            sourceApp: record["sourceApp"] as? String ?? "",
            sourceURL: record["sourceURL"] as? String ?? "",
            rawCaptureText: record["rawCaptureText"] as? String ?? "",
            sourceCaptureID: record["sourceCaptureID"] as? String ?? "",
            projectID: record["projectID"] as? String,
            projectName: record["projectName"] as? String)
    }

    private static func agentRunPayload(from record: CKRecord) -> AgentRunPayload {
        AgentRunPayload(
            id: record.recordID.recordName,
            taskID: record["taskID"] as? String ?? "",
            projectID: record["projectID"] as? String,
            taskTitleSnapshot: record["taskTitleSnapshot"] as? String ?? "Untitled Task",
            projectNameSnapshot: record["projectNameSnapshot"] as? String,
            targetRawValue: record["targetRawValue"] as? String ?? AgentTarget.codex.rawValue,
            statusRawValue: record["statusRawValue"] as? String ?? AgentRunStatus.prepared.rawValue,
            promptSnapshot: record["promptSnapshot"] as? String ?? "",
            repositoryPathSnapshot: record["repositoryPathSnapshot"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? .now,
            updatedAt: record["updatedAt"] as? Date ?? .now,
            startedAt: record["startedAt"] as? Date,
            finishedAt: record["finishedAt"] as? Date,
            resultSummary: record["resultSummary"] as? String ?? "",
            evidenceURLString: record["evidenceURLString"] as? String ?? "",
            errorMessage: record["errorMessage"] as? String ?? "",
            preparationKey: record["preparationKey"] as? String ?? "")
    }

    private static func tombstonePayload(from record: CKRecord) -> TombstonePayload {
        TombstonePayload(
            recordKind: record["recordKind"] as? String ?? "",
            recordID: record["recordIDValue"] as? String ?? "",
            taskHandling: record["taskHandling"] as? String,
            deletedAt: record["deletedAt"] as? Date ?? .now)
    }

    private static func writeDiagnostic(_ line: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShipBarDirectCloudSync.txt")
        let entry = "\(Date()) \(line)\n"
        if let data = entry.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: url)
        {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
