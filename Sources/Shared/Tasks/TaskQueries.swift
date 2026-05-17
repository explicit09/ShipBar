import Foundation

enum TaskQueries {
    static func inboxTasks(from tasks: [ShipTask]) -> [ShipTask] {
        filteredTasks(from: tasks, filter: .inbox)
    }

    static func todayTasks(from tasks: [ShipTask]) -> [ShipTask] {
        filteredTasks(from: tasks, filter: .open)
    }

    static func filteredTasks(from tasks: [ShipTask], filter: TaskFilter) -> [ShipTask] {
        tasks
            .filter { task in
                if !filter.includeDone, task.status == .done {
                    return false
                }
                if filter.inboxOnly, !task.isInbox {
                    return false
                }
                if !filter.inboxOnly, task.isInbox {
                    return false
                }
                if let status = filter.status, task.status != status {
                    return false
                }
                if let priority = filter.priority, task.priority != priority {
                    return false
                }
                if let type = filter.type, task.type != type {
                    return false
                }
                if let projectID = filter.projectID, task.project?.id != projectID {
                    return false
                }
                if filter.promptReadyOnly, !task.hasPrompt {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func tasks(for project: Project, from tasks: [ShipTask]) -> [ShipTask] {
        filteredTasks(from: tasks, filter: TaskFilter(projectID: project.id))
    }
}
