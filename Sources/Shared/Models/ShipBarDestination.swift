import Foundation

enum ShipBarDestination: String, CaseIterable, Identifiable {
    case today
    case inbox
    case runs
    case projects
    case settings

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .runs: "Runs"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "checkmark.circle"
        case .inbox: "tray"
        case .runs: "paperplane"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }

    var shortcutNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    func actionableCount(tasks: [ShipTask], runs: [AgentRun]) -> Int? {
        switch self {
        case .today:
            let groups = TaskQueries.todayGroups(from: tasks, runs: runs)
            return (groups.now == nil ? 0 : 1) + groups.next.count + groups.waiting.count
        case .inbox:
            return TaskQueries.inboxTasks(from: tasks).count
        case .runs:
            let queues = AgentRunQueries.queues(from: runs)
            return queues.needsReview.count + queues.recent.filter { $0.status == .failed }.count
        case .projects, .settings:
            return nil
        }
    }
}
