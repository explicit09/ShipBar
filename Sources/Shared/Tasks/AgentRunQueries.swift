import Foundation

struct AgentRunQueues {
    let needsReview: [AgentRun]
    let active: [AgentRun]
    let recent: [AgentRun]
}

enum AgentRunQueries {
    static func queues(from runs: [AgentRun]) -> AgentRunQueues {
        let sorted = runs.sorted { $0.updatedAt > $1.updatedAt }
        return AgentRunQueues(
            needsReview: sorted.filter { $0.status == .needsReview },
            active: sorted.filter { [.prepared, .handedOff, .running].contains($0.status) },
            recent: sorted.filter { [.completed, .failed, .canceled].contains($0.status) })
    }

    static func latest(for taskID: String, from runs: [AgentRun]) -> AgentRun? {
        runs
            .filter { $0.taskID == taskID }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
