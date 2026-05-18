import CloudKit
import Foundation
import SwiftData

enum ShipBarDirectCloudSync {
    private static let taskRecordType = "ShipBarDirectTask"
    private static let projectRecordType = "ShipBarDirectProject"
    private static let manifestRecordType = "ShipBarDirectManifest"
    private static let manifestRecordName = "current"

    private struct ProjectSnapshot: Sendable {
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

    private struct TaskSnapshot: Sendable {
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

    @MainActor
    static func sync(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).map {
            ProjectSnapshot(
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
            TaskSnapshot(
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
        let database = CKContainer(identifier: ShipBarModelContainer.cloudKitIdentifier).privateCloudDatabase

        Task.detached {
            Self.writeDiagnostic("sync start localProjects=\(projects.count) localTasks=\(tasks.count)")
            await Self.push(projects: projects, tasks: tasks, to: database)
            let manifest = await Self.fetchManifest(from: database)
            let remoteProjects = await Self.fetchRecords(ids: manifest.projectIDs, from: database)
            let remoteTasks = await Self.fetchRecords(ids: manifest.taskIDs, from: database)
            Self.writeDiagnostic("sync fetched remoteProjects=\(remoteProjects.count) remoteTasks=\(remoteTasks.count)")
            await MainActor.run {
                Self.apply(remoteProjects: remoteProjects, remoteTasks: remoteTasks, to: modelContainer)
            }
        }
    }

    private static func push(projects: [ProjectSnapshot], tasks: [TaskSnapshot], to database: CKDatabase) async {
        let projectRecords = projects.map { project in
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
        let taskRecords = tasks.map { task in
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

        let manifest = CKRecord(
            recordType: Self.manifestRecordType,
            recordID: CKRecord.ID(recordName: Self.manifestRecordName))
        manifest["projectIDs"] = projects.map(\.id) as NSArray
        manifest["taskIDs"] = tasks.map(\.id) as NSArray

        do {
            _ = try await database.modifyRecords(saving: projectRecords + taskRecords + [manifest], deleting: [])
            Self.writeDiagnostic("push saved projects=\(projectRecords.count) tasks=\(taskRecords.count)")
        } catch {
            Self.writeDiagnostic("push failed: \(error)")
            print("Direct CloudKit push failed: \(error)")
        }
    }

    private static func fetchManifest(from database: CKDatabase) async -> (projectIDs: [String], taskIDs: [String]) {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.manifestRecordName))
            let projectIDs = record["projectIDs"] as? [String] ?? []
            let taskIDs = record["taskIDs"] as? [String] ?? []
            Self.writeDiagnostic("manifest fetched projects=\(projectIDs.count) tasks=\(taskIDs.count)")
            return (projectIDs, taskIDs)
        } catch {
            Self.writeDiagnostic("manifest fetch failed: \(error)")
            return ([], [])
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
    private static func apply(remoteProjects: [CKRecord], remoteTasks: [CKRecord], to modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let localProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let localTasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        var projectsByID = Dictionary(uniqueKeysWithValues: localProjects.map { ($0.id, $0) })

        for record in remoteProjects where projectsByID[record.recordID.recordName] == nil {
            let project = Project(
                id: record.recordID.recordName,
                name: record["name"] as? String ?? "Project",
                basePrompt: record["basePrompt"] as? String ?? "",
                repoPath: record["repoPath"] as? String ?? "",
                color: record["color"] as? String ?? "blue",
                icon: record["icon"] as? String ?? "square.stack.3d.up",
                sortOrder: record["sortOrder"] as? Int ?? localProjects.count,
                createdAt: record["createdAt"] as? Date ?? .now,
                updatedAt: record["updatedAt"] as? Date ?? .now)
            context.insert(project)
            projectsByID[project.id] = project
        }

        let localTaskIDs = Set(localTasks.map(\.id))
        for record in remoteTasks where !localTaskIDs.contains(record.recordID.recordName) {
            let projectID = record["projectID"] as? String
            let project = projectID.flatMap { projectsByID[$0] }
            context.insert(ShipTask(
                id: record.recordID.recordName,
                title: record["title"] as? String ?? "Untitled",
                taskDescription: record["taskDescription"] as? String ?? "",
                prompt: record["prompt"] as? String ?? "",
                status: TaskStatus(rawValue: record["status"] as? String ?? "") ?? .todo,
                priority: TaskPriority(rawValue: record["priority"] as? String ?? "") ?? .medium,
                type: TaskType(rawValue: record["type"] as? String ?? "") ?? .idea,
                createdAt: record["createdAt"] as? Date ?? .now,
                updatedAt: record["updatedAt"] as? Date ?? .now,
                completedAt: record["completedAt"] as? Date,
                dueDate: record["dueDate"] as? Date,
                isInbox: record["isInbox"] as? Bool ?? true,
                sourceApp: record["sourceApp"] as? String ?? "",
                sourceURL: record["sourceURL"] as? String ?? "",
                rawCaptureText: record["rawCaptureText"] as? String ?? "",
                project: project))
        }

        try? context.save()
        let finalTasks = (try? context.fetchCount(FetchDescriptor<ShipTask>())) ?? -1
        Self.writeDiagnostic("apply complete localTasks=\(finalTasks)")
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
