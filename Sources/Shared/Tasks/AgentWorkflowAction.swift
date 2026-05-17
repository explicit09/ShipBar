import Foundation

struct AgentWorkflowAction: Equatable {
    let target: AgentTarget
    let clipboardText: String
    let launchHint: String

    static func make(for target: AgentTarget, task: ShipTask) -> AgentWorkflowAction {
        AgentWorkflowAction(
            target: target,
            clipboardText: PromptComposer.agentPrompt(for: task, target: target),
            launchHint: Self.launchHint(for: target))
    }

    private static func launchHint(for target: AgentTarget) -> String {
        switch target {
        case .codex:
            "Open Codex and paste the copied prompt."
        case .claude:
            "Open a terminal in the repo and run claude, then paste the copied prompt."
        case .cursor:
            "Open Cursor and paste the copied prompt into the agent composer."
        }
    }
}
