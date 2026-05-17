import Foundation

enum TaskQueries {
    static func todayTasks(from tasks: [ShipTask]) -> [ShipTask] {
        tasks
            .filter { $0.status != .done }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func tasks(for project: Project, from tasks: [ShipTask]) -> [ShipTask] {
        todayTasks(from: tasks).filter { $0.project?.id == project.id }
    }
}
