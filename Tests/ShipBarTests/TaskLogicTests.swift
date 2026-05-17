import Foundation
import Testing

@Suite("Task logic")
struct TaskLogicTests {
    @Test("completedAt follows done status")
    func completedAtFollowsDoneStatus() {
        let task = ShipTask(title: "Ship parser")

        #expect(task.completedAt == nil)

        task.applyStatus(.done, now: Date(timeIntervalSince1970: 10))
        #expect(task.completedAt == Date(timeIntervalSince1970: 10))

        task.applyStatus(.todo, now: Date(timeIntervalSince1970: 20))
        #expect(task.completedAt == nil)
    }

    @Test("today queue includes only open tasks sorted by priority")
    func todayQueueSortsOpenTasks() {
        let low = ShipTask(title: "Low", priority: .low)
        let high = ShipTask(title: "High", priority: .high)
        let done = ShipTask(title: "Done", status: .done, priority: .high)

        let result = TaskQueries.todayTasks(from: [low, high, done])

        #expect(result.map { $0.title } == ["High", "Low"])
    }

    @Test("agent prompt combines project context and task fields")
    func agentPromptCombinesTaskContext() {
        let project = Project(
            name: "vedit",
            basePrompt: "You are working in the vedit repository. Keep timeline edits deterministic.")
        let task = ShipTask(
            title: "Add undo stack",
            taskDescription: "Support undo and redo for timeline edits.",
            prompt: "Implement the undo stack with clear command boundaries.",
            priority: .high,
            type: .feature,
            project: project)

        let prompt = PromptComposer.agentPrompt(for: task)

        #expect(prompt.contains("You are working in the vedit repository."))
        #expect(prompt.contains("Task: Add undo stack"))
        #expect(prompt.contains("Priority: High"))
        #expect(prompt.contains("Type: Feature"))
        #expect(prompt.contains("Support undo and redo for timeline edits."))
        #expect(prompt.contains("Implement the undo stack with clear command boundaries."))
    }

    @Test("targeted agent prompt names selected tool")
    func targetedAgentPromptNamesSelectedTool() {
        let task = ShipTask(title: "Add share extension", prompt: "Capture text from Safari.")

        let prompt = PromptComposer.agentPrompt(for: task, target: .codex)

        #expect(prompt.contains("Target agent: Codex"))
        #expect(prompt.contains("Capture text from Safari."))
    }

    @Test("inbox queue contains untriaged captures first")
    func inboxQueueContainsUntriagedCapturesFirst() {
        let project = Project(name: "vedit")
        let inboxCapture = ShipTask(title: "Raw note", isInbox: true)
        let projectTask = ShipTask(title: "Project task", project: project)
        let doneInbox = ShipTask(title: "Done inbox", status: .done, isInbox: true)

        let result = TaskQueries.inboxTasks(from: [projectTask, doneInbox, inboxCapture])

        #expect(result.map(\.title) == ["Raw note"])
    }

    @Test("task triage assigns project and removes inbox flag")
    func triageAssignsProjectAndRemovesInboxFlag() {
        let project = Project(name: "vedit")
        let task = ShipTask(title: "Raw note", isInbox: true)

        task.triage(project: project, status: .doing)

        #expect(task.project?.id == project.id)
        #expect(task.status == .doing)
        #expect(task.isInbox == false)
    }
}
