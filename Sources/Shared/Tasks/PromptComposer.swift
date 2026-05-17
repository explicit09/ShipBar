import Foundation

enum AgentTarget: String, CaseIterable, Identifiable {
    case codex
    case claude
    case cursor

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: "circle.hexagongrid"
        case .claude: "sparkles"
        case .cursor: "cube.fill"
        }
    }
}

enum PromptComposer {
    static func agentPrompt(for task: ShipTask, target: AgentTarget? = nil) -> String {
        let projectName = task.project?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectContext = task.project?.basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoPath = task.project?.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskDescription = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = task.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []

        if let target {
            sections.append("Target agent: \(target.label)")
        }

        if let projectContext, !projectContext.isEmpty {
            sections.append(projectContext)
        } else if let projectName, !projectName.isEmpty {
            sections.append("You are working in the \(projectName) project.")
        }

        if let repoPath, !repoPath.isEmpty {
            sections.append("Repository path: \(repoPath)")
        }

        var taskLines = [
            "Task: \(task.title)",
            "Status: \(task.status.label)",
            "Priority: \(task.priority.label)",
            "Type: \(task.type.label)",
        ]
        if !taskDescription.isEmpty {
            taskLines.append("Description: \(taskDescription)")
        }
        sections.append(taskLines.joined(separator: "\n"))

        if !taskPrompt.isEmpty {
            sections.append(taskPrompt)
        } else {
            sections.append("Implement this task in the smallest useful way. Keep the change focused and verify it before stopping.")
        }

        return sections.joined(separator: "\n\n")
    }
}
