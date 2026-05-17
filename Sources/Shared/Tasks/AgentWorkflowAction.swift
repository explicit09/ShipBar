import Foundation

struct AgentWorkflowAction: Equatable {
    let target: AgentTarget
    let repoPath: String
    let clipboardText: String
    let launchHint: String

    static func make(for target: AgentTarget, task: ShipTask) -> AgentWorkflowAction {
        let repoPath = task.project?.repoPath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AgentWorkflowAction(
            target: target,
            repoPath: repoPath,
            clipboardText: PromptComposer.agentPrompt(for: task, target: target),
            launchHint: Self.launchHint(for: target, repoPath: repoPath))
    }

    private static func launchHint(for target: AgentTarget, repoPath: String) -> String {
        let repoHint = repoPath.isEmpty ? "" : " using \(repoPath)"
        switch target {
        case .codex:
            return "Open Codex\(repoHint) and paste the copied prompt."
        case .claude:
            return "Open a terminal\(repoHint) and run claude, then paste the copied prompt."
        case .cursor:
            return "Open Cursor\(repoHint) and paste the copied prompt into the agent composer."
        }
    }
}
