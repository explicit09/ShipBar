import Foundation
import SwiftData

enum ShipBarProjectTaskHandling: String, Codable {
    case deleteTasks
    case moveToInbox
}

enum ShipBarProjectLifecycle {
    @MainActor
    static func delete(
        _ project: Project,
        taskHandling: ShipBarProjectTaskHandling,
        deletedAt: Date = .now,
        in context: ModelContext)
    {
        let projectID = project.id
        let tasks = Self.tasks(for: project, in: context)

        ShipBarDeletionLog.record(
            .project,
            id: projectID,
            taskHandling: taskHandling.rawValue,
            deletedAt: deletedAt,
            in: context)

        switch taskHandling {
        case .deleteTasks:
            for task in tasks {
                ShipBarTaskLifecycle.delete(task, deletedAt: deletedAt, in: context)
            }
        case .moveToInbox:
            for task in tasks {
                task.project = nil
                task.isInbox = true
                task.updatedAt = deletedAt
            }
            project.tasks = []
        }

        context.delete(project)
    }

    @MainActor
    private static func tasks(for project: Project, in context: ModelContext) -> [ShipTask] {
        let tasks = (try? context.fetch(FetchDescriptor<ShipTask>())) ?? []
        return tasks.filter { $0.project?.id == project.id }
    }
}

enum ShipBarTaskLifecycle {
    @MainActor
    static func delete(_ task: ShipTask, deletedAt: Date = .now, in context: ModelContext) {
        ShipBarDeletionLog.record(.task, id: task.id, deletedAt: deletedAt, in: context)
        context.delete(task)
    }
}

enum ShipBarProjectNaming {
    static func newProjectName(existing projects: [Project]) -> String {
        let names = Set(projects.map(\.name))
        let base = "New Project"
        guard names.contains(base) else { return base }

        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}
