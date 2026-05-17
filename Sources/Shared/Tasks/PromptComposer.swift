import Foundation

enum PromptComposer {
    static func agentPrompt(for task: ShipTask) -> String {
        let projectName = task.project?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectContext = task.project?.basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskDescription = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = task.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []

        if let projectContext, !projectContext.isEmpty {
            sections.append(projectContext)
        } else if let projectName, !projectName.isEmpty {
            sections.append("You are working in the \(projectName) project.")
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
