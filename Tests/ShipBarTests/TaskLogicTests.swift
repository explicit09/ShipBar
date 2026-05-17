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

    @Test("filters queue by status priority type and prompt readiness")
    func filtersQueueByMetadata() {
        let feature = ShipTask(title: "Feature", prompt: "Build it", status: .doing, priority: .high, type: .feature)
        let bug = ShipTask(title: "Bug", status: .todo, priority: .high, type: .bug)
        let chore = ShipTask(title: "Chore", prompt: "Clean it", status: .doing, priority: .low, type: .chore)
        let filter = TaskFilter(status: .doing, priority: .high, type: .feature, promptReadyOnly: true)

        let result = TaskQueries.filteredTasks(from: [bug, chore, feature], filter: filter)

        #expect(result.map(\.title) == ["Feature"])
    }

    @Test("filter presets expose inbox and prompt ready queues")
    func filterPresetsExposeInboxAndPromptReadyQueues() {
        let inbox = ShipTask(title: "Inbox", isInbox: true)
        let prompt = ShipTask(title: "Prompt", prompt: "Ship it")
        let plain = ShipTask(title: "Plain")

        let inboxResult = TaskQueries.filteredTasks(from: [inbox, prompt, plain], filter: .inbox)
        let promptResult = TaskQueries.filteredTasks(from: [inbox, prompt, plain], filter: .promptReady)

        #expect(inboxResult.map(\.title) == ["Inbox"])
        #expect(promptResult.map(\.title) == ["Prompt"])
    }

    @Test("agent prompt combines project context and task fields")
    func agentPromptCombinesTaskContext() {
        let project = Project(
            name: "vedit",
            basePrompt: "You are working in the vedit repository. Keep timeline edits deterministic.",
            repoPath: "/Users/max/Projects/vedit")
        let task = ShipTask(
            title: "Add undo stack",
            taskDescription: "Support undo and redo for timeline edits.",
            prompt: "Implement the undo stack with clear command boundaries.",
            priority: .high,
            type: .feature,
            project: project)

        let prompt = PromptComposer.agentPrompt(for: task)

        #expect(prompt.contains("You are working in the vedit repository."))
        #expect(prompt.contains("Repository path: /Users/max/Projects/vedit"))
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

    @Test("agent action copies prompt and gives launch hint")
    func agentActionCopiesPromptAndGivesLaunchHint() {
        let project = Project(name: "ShipBar", repoPath: "/Users/max/Projects/ShipBar")
        let task = ShipTask(title: "Add filters", prompt: "Implement task filters.", project: project)

        let action = AgentWorkflowAction.make(for: .claude, task: task)

        #expect(action.repoPath == "/Users/max/Projects/ShipBar")
        #expect(action.clipboardText.contains("Target agent: Claude Code"))
        #expect(action.clipboardText.contains("Repository path: /Users/max/Projects/ShipBar"))
        #expect(action.launchHint.contains("claude"))
        #expect(action.launchHint.contains("/Users/max/Projects/ShipBar"))
    }

    @Test("agent handoff moves open task to doing and records history")
    func agentHandoffMovesOpenTaskToDoingAndRecordsHistory() {
        let task = ShipTask(title: "Add row handoff", prompt: "Add task row agent actions.")

        let action = task.beginAgentHandoff(to: .codex, now: Date(timeIntervalSince1970: 30))

        #expect(task.status == .doing)
        #expect(task.updatedAt == Date(timeIntervalSince1970: 30))
        #expect(task.completedAt == nil)
        #expect(task.lastAgentTarget == .codex)
        #expect(task.lastAgentHandoffAt == Date(timeIntervalSince1970: 30))
        #expect(task.agentHandoffCount == 1)
        #expect(action.clipboardText.contains("Target agent: Codex"))
    }

    @Test("agent handoff does not reopen completed task")
    func agentHandoffDoesNotReopenCompletedTask() {
        let doneAt = Date(timeIntervalSince1970: 10)
        let task = ShipTask(title: "Already shipped", status: .done, completedAt: doneAt)

        _ = task.beginAgentHandoff(to: .cursor, now: Date(timeIntervalSince1970: 30))

        #expect(task.status == .done)
        #expect(task.completedAt == doneAt)
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

        task.triage(project: project, status: .doing, priority: .high, type: .feature)

        #expect(task.project?.id == project.id)
        #expect(task.status == .doing)
        #expect(task.priority == .high)
        #expect(task.type == .feature)
        #expect(task.isInbox == false)
    }

    @Test("CloudKit diagnostics require container and service entitlements")
    func cloudKitDiagnosticsRequireContainerAndServiceEntitlements() {
        let enabled = ShipBarModelContainer.diagnostics(
            containerIdentifiers: [ShipBarModelContainer.cloudKitIdentifier],
            services: ["CloudKit"])
        let missingContainer = ShipBarModelContainer.diagnostics(
            containerIdentifiers: [],
            services: ["CloudKit"])
        let missingService = ShipBarModelContainer.diagnostics(
            containerIdentifiers: [ShipBarModelContainer.cloudKitIdentifier],
            services: [])

        #expect(enabled.isEnabledForCurrentBuild)
        #expect(enabled.statusText == "Enabled")
        #expect(missingContainer.isEnabledForCurrentBuild == false)
        #expect(missingContainer.detailText.contains("missing the \(ShipBarModelContainer.cloudKitIdentifier)"))
        #expect(missingService.isEnabledForCurrentBuild == false)
        #expect(missingService.detailText.contains("missing the CloudKit service"))
    }
}
