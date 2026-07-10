import CloudKit
import Foundation
import SwiftData

enum ShipBarDirectCloudSync {
    private static let taskRecordType = "ShipBarDirectTask"
    private static let projectRecordType = "ShipBarDirectProject"
    private static let tombstoneRecordType = "ShipBarDirectTombstone"
    private static let manifestRecordType = "ShipBarDirectManifest"
    private static let manifestRecordName = "current"

    struct ProjectPayload: Sendable {
        let id: String
        let name: String
        let basePrompt: String
        let repoPath: String
        let color: String
        let icon: String
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
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
        let isInbox: Bool
        let sourceApp: String
        let sourceURL: String
        let rawCaptureText: String
        let projectID: String?
        let projectName: String?
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
        let tombstones: [TombstonePayload]
    }

    @MainActor
    static func sync(modelContainer: ModelContainer) {
        let database = CKContainer(identifier: ShipBarModelContainer.cloudKitIdentifier).privateCloudDatabase

        Task.detached {
            Self.writeDiagnostic("sync start")
            let manifest = await Self.fetchManifest(from: database)
            let remoteProjects = await Self.fetchRecords(ids: manifest.projectIDs, from: database)
            let remoteTasks = await Self.fetchRecords(ids: manifest.taskIDs, from: database)
            let remoteTombstones = await Self.fetchRecords(ids: manifest.tombstoneIDs, from: database)
            Self.writeDiagnostic("sync fetched remoteProjects=\(remoteProjects.count) remoteTasks=\(remoteTasks.count) tombstones=\(remoteTombstones.count)")
            await MainActor.run {
                Self.apply(
                    remoteProjects: remoteProjects,
                    remoteTasks: remoteTasks,
                    remoteTombstones: remoteTombstones,
                    to: modelContainer)
            }

            let localPayloads = await MainActor.run {
                Self.localPayloads(from: modelContainer)
            }
            Self.writeDiagnostic("sync push localProjects=\(localPayloads.projects.count) localTasks=\(localPayloads.tasks.count) tombstones=\(localPayloads.tombstones.count)")
            await Self.push(
                projects: localPayloads.projects,
                tasks: localPayloads.tasks,
                tombstones: localPayloads.tombstones,
                to: database)
            #if DEBUG
            let postPushManifest = await Self.fetchManifest(from: database)
            Self.writeDiagnostic("post-push manifest projects=\(postPushManifest.projectIDs.count) tasks=\(postPushManifest.taskIDs.count) tombstones=\(postPushManifest.tombstoneIDs.count)")
            #endif
        }
    }

    @MainActor
    private static func localPayloads(from modelContainer: ModelContainer) -> LocalPayloads {
        let context = ModelContext(modelContainer)
        let cleanup = ShipBarLocalDuplicateResolver.cleanup(in: context)
        if cleanup.didChange {
            ShipBarPersistence.save(context, operation: "Preflight sync cleanup")
            Self.writeDiagnostic("preflight cleanup updatedProjects=\(cleanup.updatedProjects) deletedProjects=\(cleanup.deletedProjects) deletedTasks=\(cleanup.deletedTasks)")
        }

        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).map {
            ProjectPayload(
                id: $0.id,
                name: $0.name,
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
                isInbox: $0.isInbox,
                sourceApp: $0.sourceApp,
                sourceURL: $0.sourceURL,
                rawCaptureText: $0.rawCaptureText,
                projectID: $0.project?.id,
                projectName: $0.project?.name)
        }
        let tombstones = ShipBarDeletionLog.tombstones(in: context).map {
            TombstonePayload(
                recordKind: $0.recordKind,
                recordID: $0.recordID,
                taskHandling: $0.taskHandling,
                deletedAt: $0.deletedAt)
        }
        return LocalPayloads(projects: projects, tasks: tasks, tombstones: tombstones)
    }

    private static func push(
        projects: [ProjectPayload],
        tasks: [TaskPayload],
        tombstones: [TombstonePayload],
        to database: CKDatabase) async
    {
        let deletedProjectIDs = Set(tombstones.filter { $0.recordKind == ShipBarDeletionKind.project.rawValue }.map(\.recordID))
        let deletedTaskIDs = Set(tombstones.filter { $0.recordKind == ShipBarDeletionKind.task.rawValue }.map(\.recordID))
        let liveProjects = projects.filter { !deletedProjectIDs.contains($0.id) }
        let liveTasks = tasks.filter { !deletedTaskIDs.contains($0.id) && !deletedProjectIDs.contains($0.projectID ?? "") }

        let projectRecords = liveProjects.map { project in
            let record = CKRecord(recordType: Self.projectRecordType, recordID: CKRecord.ID(recordName: project.id))
            record["name"] = project.name
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
            record["isInbox"] = task.isInbox
            record["sourceApp"] = task.sourceApp
            record["sourceURL"] = task.sourceURL
            record["rawCaptureText"] = task.rawCaptureText
            record["projectID"] = task.projectID
            record["projectName"] = task.projectName
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

        let manifest = CKRecord(
            recordType: Self.manifestRecordType,
            recordID: CKRecord.ID(recordName: Self.manifestRecordName))
        Self.setStringList(liveProjects.map(\.id), for: "projectIDs", on: manifest)
        Self.setStringList(liveTasks.map(\.id), for: "taskIDs", on: manifest)
        Self.setStringList(tombstones.map(\.cloudRecordName), for: "tombstoneIDs", on: manifest)

        do {
            let recordsToDelete = tombstones.compactMap(Self.deletedRecordID(for:))
            try await Self.modifyRecords(
                saving: projectRecords + taskRecords + tombstoneRecords + [manifest],
                deleting: [],
                in: database,
                savePolicy: .allKeys)
            Self.writeDiagnostic("push saved projects=\(projectRecords.count) tasks=\(taskRecords.count) tombstones=\(tombstoneRecords.count)")
            await Self.deleteObsoleteRecords(recordsToDelete, from: database)
        } catch {
            Self.writeDiagnostic("push failed: \(error)")
            print("Direct CloudKit push failed: \(error)")
        }
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
            var recordErrors: [String] = []
            operation.perRecordSaveBlock = { recordID, saveResult in
                switch saveResult {
                case .success(let record) where recordID.recordName == Self.manifestRecordName:
                    let projectIDs = record["projectIDs"] as? [String] ?? []
                    let taskIDs = record["taskIDs"] as? [String] ?? []
                    let tombstoneIDs = record["tombstoneIDs"] as? [String] ?? []
                    Self.writeDiagnostic("manifest save callback projects=\(projectIDs.count) tasks=\(taskIDs.count) tombstones=\(tombstoneIDs.count)")
                case .success:
                    break
                case .failure(let error):
                    let message = "record save failed id=\(recordID.recordName): \(error)"
                    Self.writeDiagnostic(message)
                    errorLock.lock()
                    recordErrors.append(message)
                    errorLock.unlock()
                }
            }
            operation.modifyRecordsResultBlock = { result in
                errorLock.lock()
                let errors = recordErrors
                errorLock.unlock()
                guard errors.isEmpty else {
                    continuation.resume(throwing: NSError(
                        domain: "ShipBarDirectCloudSync",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")]))
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

    private static func fetchManifest(from database: CKDatabase) async -> (projectIDs: [String], taskIDs: [String], tombstoneIDs: [String]) {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.manifestRecordName))
            let projectIDs = record["projectIDs"] as? [String] ?? []
            let taskIDs = record["taskIDs"] as? [String] ?? []
            let tombstoneIDs = record["tombstoneIDs"] as? [String] ?? []
            Self.writeDiagnostic("manifest fetched projects=\(projectIDs.count) tasks=\(taskIDs.count) tombstones=\(tombstoneIDs.count)")
            return (projectIDs, taskIDs, tombstoneIDs)
        } catch {
            Self.writeDiagnostic("manifest fetch failed: \(error)")
            return ([], [], [])
        }
    }

    private static func fetchRecords(ids: [String], from database: CKDatabase) async -> [CKRecord] {
        guard !ids.isEmpty else { return [] }
        do {
            let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
            let results = try await database.records(for: recordIDs)
            return results.compactMap { try? $0.value.get() }
        } catch {
            Self.writeDiagnostic("record fetch failed count=\(ids.count): \(error)")
            return []
        }
    }

    @MainActor
    static func applyPayload(
        projects remoteProjects: [ProjectPayload],
        tasks remoteTasks: [TaskPayload],
        tombstones remoteTombstones: [TombstonePayload],
        to modelContainer: ModelContainer)
    {
        let context = ModelContext(modelContainer)
        let localProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let localTasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        var projectsByID = Dictionary(uniqueKeysWithValues: localProjects.map { ($0.id, $0) })
        var tasksByID = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })

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
                    tasksByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<ShipTask>())) ?? []).map { ($0.id, $0) })
                }
            case .task:
                if let task = tasksByID[tombstone.recordID] {
                    context.delete(task)
                    tasksByID.removeValue(forKey: tombstone.recordID)
                }
            }
        }

        let deletedProjectHandling = Dictionary(uniqueKeysWithValues: remoteTombstones
            .filter { $0.recordKind == ShipBarDeletionKind.project.rawValue }
            .map {
                (
                    $0.recordID,
                    ShipBarProjectTaskHandling(rawValue: $0.taskHandling ?? "") ?? .deleteTasks
                )
            })
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

        let cleanup = ShipBarLocalDuplicateResolver.cleanup(in: context)
        ShipBarPersistence.save(context, operation: "Apply direct CloudKit payload")
        let finalTasks = (try? context.fetchCount(FetchDescriptor<ShipTask>())) ?? -1
        Self.writeDiagnostic("apply complete localTasks=\(finalTasks) updatedProjects=\(cleanup.updatedProjects) deletedProjects=\(cleanup.deletedProjects) deletedTasks=\(cleanup.deletedTasks)")
    }

    @MainActor
    private static func apply(
        remoteProjects: [CKRecord],
        remoteTasks: [CKRecord],
        remoteTombstones: [CKRecord],
        to modelContainer: ModelContainer)
    {
        Self.applyPayload(
            projects: remoteProjects.map(Self.projectPayload(from:)),
            tasks: remoteTasks.map(Self.taskPayload(from:)),
            tombstones: remoteTombstones.map(Self.tombstonePayload(from:)),
            to: modelContainer)
    }

    private static func makeProject(from payload: ProjectPayload, fallbackSortOrder: Int) -> Project {
        Project(
            id: payload.id,
            name: payload.name,
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
        task.isInbox = forceInbox ? true : payload.isInbox
        task.sourceApp = payload.sourceApp
        task.sourceURL = payload.sourceURL
        task.rawCaptureText = payload.rawCaptureText
        task.project = forceInbox ? nil : project
    }

    private static func projectPayload(from record: CKRecord) -> ProjectPayload {
        ProjectPayload(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "Project",
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
            isInbox: record["isInbox"] as? Bool ?? true,
            sourceApp: record["sourceApp"] as? String ?? "",
            sourceURL: record["sourceURL"] as? String ?? "",
            rawCaptureText: record["rawCaptureText"] as? String ?? "",
            projectID: record["projectID"] as? String,
            projectName: record["projectName"] as? String)
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
