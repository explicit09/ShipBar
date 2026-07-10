import Foundation
import SwiftData

enum ShipBarV2PreviewData {
    static let environmentKey = "SHIPBAR_V2_PREVIEW_DATA"

    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[Self.environmentKey] == "1"
    }

    @MainActor
    static func seed(in context: ModelContext, now: Date = .now) {
        let day = Calendar.current.startOfDay(for: now)
        let project = Project(
            id: "preview.v2.project",
            name: "ShipBar V2",
            outcome: "A calm cockpit that makes shipping visible and trustworthy.",
            basePrompt: "Work from the V2 spec. Preserve native platform behavior and attach proof.",
            repoPath: "/Users/tadies/Documents/ShipBar",
            color: "blue")

        let nowTask = ShipTask(
            id: "preview.v2.task.now",
            title: "Polish the shipping cockpit",
            prompt: "Tighten the command center hierarchy and verify it at 420 by 620.",
            priority: .high,
            dueDate: day,
            focusDate: day,
            focusOrder: 1,
            project: project)
        let nextTask = ShipTask(
            id: "preview.v2.task.next",
            title: "Verify command palette ranking",
            prompt: "Exercise navigation, task, project, and run search results.",
            dueDate: day,
            focusDate: day,
            focusOrder: 2,
            project: project)
        let waitingTask = ShipTask(
            id: "preview.v2.task.waiting",
            title: "Agent is checking CloudKit sync",
            prompt: "Verify every V2 field round-trips through direct CloudKit sync.",
            status: .doing,
            focusDate: day,
            focusOrder: 3,
            project: project)
        let reviewTask = ShipTask(
            id: "preview.v2.task.review",
            title: "Review accessibility evidence",
            prompt: "Audit labels, focus order, contrast, and reduce-motion behavior.",
            status: .doing,
            project: project)
        let failedTask = ShipTask(
            id: "preview.v2.task.failed",
            title: "Recover failed agent launch",
            prompt: "Show a truthful failure and a clear recovery path.",
            project: project)
        let completedTask = ShipTask(
            id: "preview.v2.task.completed",
            title: "Persist the daily Top 3",
            status: .done,
            completedAt: day.addingTimeInterval(10 * 60 * 60),
            project: project)
        let inboxOne = ShipTask(id: "preview.v2.task.inbox.1", title: "Triage competitor notes", isInbox: true)
        let inboxTwo = ShipTask(id: "preview.v2.task.inbox.2", title: "Schedule launch checklist", isInbox: true)

        let runs = [
            AgentRun(
                id: "preview.v2.run.prepared",
                taskID: nextTask.id,
                projectID: project.id,
                taskTitleSnapshot: nextTask.title,
                projectNameSnapshot: project.name,
                statusRawValue: AgentRunStatus.prepared.rawValue,
                promptSnapshot: nextTask.prompt,
                repositoryPathSnapshot: project.repoPath,
                updatedAt: now.addingTimeInterval(-300)),
            AgentRun(
                id: "preview.v2.run.running",
                taskID: waitingTask.id,
                projectID: project.id,
                taskTitleSnapshot: waitingTask.title,
                projectNameSnapshot: project.name,
                statusRawValue: AgentRunStatus.running.rawValue,
                promptSnapshot: waitingTask.prompt,
                repositoryPathSnapshot: project.repoPath,
                updatedAt: now.addingTimeInterval(-60),
                startedAt: now.addingTimeInterval(-900)),
            AgentRun(
                id: "preview.v2.run.review",
                taskID: reviewTask.id,
                projectID: project.id,
                taskTitleSnapshot: reviewTask.title,
                projectNameSnapshot: project.name,
                statusRawValue: AgentRunStatus.needsReview.rawValue,
                promptSnapshot: reviewTask.prompt,
                repositoryPathSnapshot: project.repoPath,
                updatedAt: now.addingTimeInterval(-120),
                finishedAt: now.addingTimeInterval(-600),
                resultSummary: "Added combined labels, visible focus treatment, and non-color state text.",
                evidenceURLString: "file:///tmp/shipbar-v2-accessibility-evidence.html"),
            AgentRun(
                id: "preview.v2.run.completed",
                taskID: completedTask.id,
                projectID: project.id,
                taskTitleSnapshot: completedTask.title,
                projectNameSnapshot: project.name,
                statusRawValue: AgentRunStatus.completed.rawValue,
                updatedAt: now.addingTimeInterval(-1_800),
                finishedAt: now.addingTimeInterval(-1_800),
                resultSummary: "Top 3 persists and normalizes after completion."),
            AgentRun(
                id: "preview.v2.run.failed",
                taskID: failedTask.id,
                projectID: project.id,
                taskTitleSnapshot: failedTask.title,
                projectNameSnapshot: project.name,
                statusRawValue: AgentRunStatus.failed.rawValue,
                updatedAt: now.addingTimeInterval(-2_400),
                finishedAt: now.addingTimeInterval(-2_400),
                errorMessage: "Agent application was unavailable. Prompt remains ready to copy."),
        ]

        context.insert(project)
        for task in [nowTask, nextTask, waitingTask, reviewTask, failedTask, completedTask, inboxOne, inboxTwo] {
            context.insert(task)
        }
        for run in runs { context.insert(run) }
        ShipBarPersistence.save(context, operation: "Seed isolated V2 preview data")
    }
}
