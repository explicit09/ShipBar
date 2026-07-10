import Foundation

struct ProjectHealth: Equatable {
    let openCount: Int
    let focusCount: Int
    let activeRunCount: Int
    let completedCount: Int

    var progress: Double {
        let total = self.openCount + self.completedCount
        guard total > 0 else { return 0 }
        return Double(self.completedCount) / Double(total)
    }
}

enum ProjectQueries {
    static func health(project: Project, tasks: [ShipTask], runs: [AgentRun]) -> ProjectHealth {
        let projectTasks = tasks.filter { $0.project?.id == project.id }
        let activeStatuses: Set<AgentRunStatus> = [.prepared, .handedOff, .running, .needsReview]
        return ProjectHealth(
            openCount: projectTasks.count { $0.status != .done },
            focusCount: projectTasks.count { $0.status != .done && $0.focusOrder != nil },
            activeRunCount: runs.count { $0.projectID == project.id && activeStatuses.contains($0.status) },
            completedCount: projectTasks.count { $0.status == .done })
    }
}
