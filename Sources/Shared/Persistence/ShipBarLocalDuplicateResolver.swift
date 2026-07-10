import Foundation
import SwiftData

struct ShipBarDuplicateCleanupResult: Equatable {
    var updatedProjects: Int = 0
    var deletedProjects: Int = 0
    var deletedTasks: Int = 0

    var didChange: Bool {
        self.updatedProjects > 0 || self.deletedProjects > 0 || self.deletedTasks > 0
    }
}

enum ShipBarLocalDuplicateResolver {
    @MainActor
    @discardableResult
    static func cleanup(in context: ModelContext) -> ShipBarDuplicateCleanupResult {
        var result = ShipBarDuplicateCleanupResult()
        result.deletedProjects += Self.mergeDuplicateProjects(in: context)
        result.updatedProjects += Self.canonicalizeDefaultProjectIDs(in: context)
        result.deletedTasks += Self.deleteDuplicateTasks(in: context)
        return result
    }

    @MainActor
    private static func mergeDuplicateProjects(in context: ModelContext) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let mergeableGroups = Dictionary(grouping: projects) { project in
            ShipBarDefaultData.normalizedName(project.name)
        }
        .filter { name, projects in
            projects.count > 1 && (
                ShipBarDefaultData.defaultProjectIDsByName[name] != nil ||
                    Self.projectsHaveIdenticalContent(projects)
            )
        }

        guard !mergeableGroups.isEmpty else { return 0 }

        let tasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        var projectsToDelete: [Project] = []
        var deleted = 0

        for (name, duplicates) in mergeableGroups {
            guard let survivor = Self.preferredProject(from: duplicates, normalizedName: name) else { continue }
            for duplicate in duplicates where duplicate !== survivor {
                for task in tasks where task.project?.id == duplicate.id {
                    task.project = survivor
                    task.isInbox = false
                }
                Self.mergeProjectFields(from: duplicate, into: survivor)
                duplicate.tasks = []
                projectsToDelete.append(duplicate)
                deleted += 1
            }
        }

        ShipBarPersistence.save(context, operation: "Prepare duplicate project merge")
        for project in projectsToDelete {
            context.delete(project)
        }

        return deleted
    }

    @MainActor
    private static func canonicalizeDefaultProjectIDs(in context: ModelContext) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let usedIDs = Set(projects.map(\.id))
        var updated = 0

        for project in projects {
            let normalizedName = ShipBarDefaultData.normalizedName(project.name)
            guard let canonicalID = ShipBarDefaultData.defaultProjectIDsByName[normalizedName],
                  project.id != canonicalID,
                  !usedIDs.contains(canonicalID)
            else { continue }
            project.id = canonicalID
            updated += 1
        }

        return updated
    }

    private static func projectsHaveIdenticalContent(_ projects: [Project]) -> Bool {
        guard let first = projects.first else { return false }
        return projects.allSatisfy { project in
            ShipBarDefaultData.normalizedName(project.name) == ShipBarDefaultData.normalizedName(first.name) &&
                project.basePrompt == first.basePrompt &&
                project.repoPath == first.repoPath &&
                project.color == first.color &&
                project.icon == first.icon
        }
    }

    private static func preferredProject(from projects: [Project], normalizedName: String) -> Project? {
        let defaultID = ShipBarDefaultData.defaultProjectIDsByName[normalizedName]
        return projects.sorted { lhs, rhs in
            if lhs.id == defaultID { return true }
            if rhs.id == defaultID { return false }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }.first
    }

    private static func mergeProjectFields(from duplicate: Project, into survivor: Project) {
        if survivor.basePrompt.isEmpty, !duplicate.basePrompt.isEmpty {
            survivor.basePrompt = duplicate.basePrompt
        }
        if survivor.repoPath.isEmpty, !duplicate.repoPath.isEmpty {
            survivor.repoPath = duplicate.repoPath
        }
        if survivor.color == "blue", duplicate.color != "blue" {
            survivor.color = duplicate.color
        }
        if survivor.icon == "square.stack.3d.up", duplicate.icon != "square.stack.3d.up" {
            survivor.icon = duplicate.icon
        }
        survivor.updatedAt = max(survivor.updatedAt, duplicate.updatedAt)
    }

    @MainActor
    private static func deleteDuplicateTasks(in context: ModelContext) -> Int {
        let tasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        let groups = Dictionary(grouping: tasks, by: Self.taskFingerprint)
            .values
            .filter { $0.count > 1 }
        var deleted = 0

        for duplicates in groups {
            guard let survivor = Self.preferredTask(from: duplicates) else { continue }
            for duplicate in duplicates where duplicate !== survivor {
                Self.mergeTaskFields(from: duplicate, into: survivor)
                context.delete(duplicate)
                deleted += 1
            }
        }

        return deleted
    }

    private static func preferredTask(from tasks: [ShipTask]) -> ShipTask? {
        tasks.sorted { lhs, rhs in
            let lhsScore = Self.completenessScore(lhs)
            let rhsScore = Self.completenessScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt < rhs.createdAt
        }.first
    }

    private static func mergeTaskFields(from duplicate: ShipTask, into survivor: ShipTask) {
        if survivor.taskDescription.isEmpty, !duplicate.taskDescription.isEmpty {
            survivor.taskDescription = duplicate.taskDescription
        }
        if survivor.prompt.isEmpty, !duplicate.prompt.isEmpty {
            survivor.prompt = duplicate.prompt
        }
        if survivor.sourceApp.isEmpty, !duplicate.sourceApp.isEmpty {
            survivor.sourceApp = duplicate.sourceApp
        }
        if survivor.sourceURL.isEmpty, !duplicate.sourceURL.isEmpty {
            survivor.sourceURL = duplicate.sourceURL
        }
        if survivor.rawCaptureText.isEmpty, !duplicate.rawCaptureText.isEmpty {
            survivor.rawCaptureText = duplicate.rawCaptureText
        }
        if survivor.project == nil, let project = duplicate.project {
            survivor.project = project
            survivor.isInbox = false
        }
        survivor.updatedAt = max(survivor.updatedAt, duplicate.updatedAt)
    }

    private static func completenessScore(_ task: ShipTask) -> Int {
        [
            task.taskDescription,
            task.prompt,
            task.sourceApp,
            task.sourceURL,
            task.rawCaptureText,
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .count + (task.project == nil ? 0 : 1)
    }

    private static func taskFingerprint(_ task: ShipTask) -> String {
        [
            Self.normalizedText(task.title),
            Self.normalizedText(task.taskDescription),
            Self.normalizedText(task.prompt),
            task.status.rawValue,
            task.priority.rawValue,
            task.type.rawValue,
            task.isInbox ? "inbox" : "project",
            ShipBarDefaultData.normalizedName(task.project?.name ?? ""),
            Self.dateKey(task.dueDate),
        ].joined(separator: "\u{1f}")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func dateKey(_ date: Date?) -> String {
        guard let date else { return "" }
        return String(Int(date.timeIntervalSince1970))
    }
}
