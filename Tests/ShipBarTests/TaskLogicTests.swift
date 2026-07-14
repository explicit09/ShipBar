import Foundation
import SwiftData
import Testing

@Suite("Task logic")
struct TaskLogicTests {
    @Test("global command copy stays compact")
    func globalCommandCopyStaysCompact() {
        #expect(ShipBarDestination.searchPrompt == "Search ShipBar")
        #expect(ShipBarDestination.capturePrompt == "Capture a task…")
    }

    @MainActor
    @Test("V2 preview fixture covers every review state")
    func v2FixtureCoversReviewStates() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        ShipBarV2PreviewData.seed(in: context, now: Date(timeIntervalSince1970: 1_720_000_000))

        let statuses = Set(try context.fetch(FetchDescriptor<AgentRun>()).map(\.status))
        #expect(statuses.isSuperset(of: [.prepared, .running, .needsReview, .completed, .failed]))
        #expect(try context.fetch(FetchDescriptor<ShipTask>()).count >= 7)
    }

    @Test("preview mode is explicitly gated")
    func previewModeIsExplicitlyGated() {
        #expect(ShipBarV2PreviewData.isEnabled(environment: [:]) == false)
        #expect(ShipBarV2PreviewData.isEnabled(environment: ["SHIPBAR_V2_PREVIEW_DATA": "1"]))
    }

    @Test("iPhone prepares desktop-only handoffs without claiming launch")
    func iphoneHandoffPolicyIsTruthful() {
        #expect(AgentLaunchPolicy.behavior(for: .codex, platform: .iOS) == .prepareForMac)
        #expect(AgentLaunchPolicy.behavior(for: .codex, platform: .macOS) == .launchLocally)
    }

    @Test("project health counts open focused active and completed work")
    func projectHealthCountsWorkflowState() {
        let project = Project(name: "ShipBar")
        let focus = ShipTask(title: "Focus", focusDate: .now, focusOrder: 1, project: project)
        let open = ShipTask(title: "Open", project: project)
        let done = ShipTask(title: "Done", status: .done, completedAt: .now, project: project)
        let run = AgentRun(
            taskID: focus.id,
            projectID: project.id,
            taskTitleSnapshot: focus.title,
            statusRawValue: AgentRunStatus.running.rawValue)

        let health = ProjectQueries.health(
            project: project,
            tasks: [focus, open, done],
            runs: [run])

        #expect(health.openCount == 2)
        #expect(health.focusCount == 1)
        #expect(health.activeRunCount == 1)
        #expect(health.completedCount == 1)
    }

    @Test("project health progress includes completed work")
    func projectHealthProgressIncludesCompletedWork() {
        let project = Project(name: "ShipBar")
        let open = ShipTask(title: "Open", project: project)
        let done = ShipTask(title: "Done", status: .done, completedAt: .now, project: project)
        let health = ProjectQueries.health(project: project, tasks: [open, done], runs: [])

        #expect(health.progress == 0.5)
    }

    @Test("project workspace query includes completed work")
    func projectWorkspaceQueryIncludesCompletedWork() {
        let project = Project(name: "ShipBar")
        let open = ShipTask(title: "Open", project: project)
        let done = ShipTask(title: "Done", status: .done, completedAt: .now, project: project)

        #expect(Set(TaskQueries.tasks(for: project, from: [open, done]).map(\.id)) == [open.id, done.id])
    }

    @Test("batch triage schedules today and someday deterministically")
    func batchTriageSchedulesTodayAndSomeday() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let first = ShipTask(title: "First", isInbox: true)
        let second = ShipTask(title: "Second", isInbox: true)

        InboxBatchCoordinator.scheduleToday([first, second], among: [first, second], on: day)
        #expect([first, second].allSatisfy { $0.isInbox == false })
        #expect([first, second].allSatisfy { Calendar.current.isDate($0.dueDate!, inSameDayAs: day) })
        #expect([first.focusOrder, second.focusOrder] == [1, 2])

        InboxBatchCoordinator.moveToSomeday([first], among: [first, second], on: day)
        #expect(first.dueDate == nil)
        #expect(first.focusDate == nil)
        #expect(first.focusOrder == nil)
        #expect(second.focusOrder == 1)
    }

    @Test("open-main launch argument exposes the runtime review window")
    func openMainLaunchArgumentExposesReviewWindow() {
        #expect(ShipBarLaunchOptions.shouldOpenMain(arguments: ["ShipBarMac", "--open-main"]))
        #expect(ShipBarLaunchOptions.shouldOpenMain(arguments: ["ShipBarMac"]) == false)
    }

    @Test("focus coordinator limits today to three ordered tasks")
    func focusCoordinatorLimitsTodayToThree() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let tasks = (1...4).map { ShipTask(title: "Task \($0)") }

        #expect(FocusCoordinator.setFocus(tasks[0], among: tasks, on: day))
        #expect(FocusCoordinator.setFocus(tasks[1], among: tasks, on: day))
        #expect(FocusCoordinator.setFocus(tasks[2], among: tasks, on: day))
        #expect(FocusCoordinator.setFocus(tasks[3], among: tasks, on: day) == false)
        #expect(tasks.compactMap(\.focusOrder).sorted() == [1, 2, 3])
    }

    @Test("focus reorder and removal compact positions")
    func focusReorderAndRemovalCompactPositions() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let tasks = [ShipTask(title: "A"), ShipTask(title: "B"), ShipTask(title: "C")]
        tasks.forEach { _ = FocusCoordinator.setFocus($0, among: tasks, on: day) }

        FocusCoordinator.moveFocus(tasks[2], to: 1, among: tasks, on: day)
        FocusCoordinator.removeFocus(tasks[0], among: tasks, on: day)

        let ordered = tasks
            .filter { $0.focusOrder != nil }
            .sorted { $0.focusOrder! < $1.focusOrder! }
        #expect(ordered.map(\.title) == ["C", "B"])
        #expect(tasks.compactMap(\.focusOrder).sorted() == [1, 2])
    }

    @Test("completing focus preserves its day and promotes the next task")
    func completingFocusPromotesNextTask() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let completed = ShipTask(title: "Completed", focusDate: day, focusOrder: 1)
        let next = ShipTask(title: "Next", focusDate: day, focusOrder: 2)
        completed.applyStatus(.done, now: day.addingTimeInterval(60))

        FocusCoordinator.normalize([completed, next], on: day)

        #expect(completed.focusDate == Calendar.current.startOfDay(for: day))
        #expect(completed.focusOrder == nil)
        #expect(next.focusOrder == 1)
        #expect(FocusCoordinator.focusedTasks(in: [completed, next], on: day).map(\.id) == [next.id])
    }

    @Test("previous-day focus does not consume today's slots")
    func previousDayFocusDoesNotConsumeTodaySlots() {
        let today = Date(timeIntervalSince1970: 1_720_000_000)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let old = ShipTask(title: "Old", focusDate: yesterday, focusOrder: 1)
        let fresh = (1...3).map { ShipTask(title: "Fresh \($0)") }

        for task in fresh {
            #expect(FocusCoordinator.setFocus(task, among: [old] + fresh, on: today))
        }

        #expect(FocusCoordinator.focusedTasks(in: [old] + fresh, on: today).count == 3)
        #expect(old.focusDate == yesterday)
    }

    @MainActor
    @Test("prepared agent run snapshots task and survives task deletion")
    func preparedAgentRunSnapshotsTask() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(name: "ShipBar", repoPath: "/tmp/ShipBar")
        let task = ShipTask(title: "Build Runs", prompt: "Implement run history.", project: project)
        context.insert(project)
        context.insert(task)

        let run = AgentRunLifecycle.prepare(
            task: task,
            target: .codex,
            in: context,
            now: Date(timeIntervalSince1970: 10))

        #expect(run.taskID == task.id)
        #expect(run.taskTitleSnapshot == "Build Runs")
        #expect(run.projectNameSnapshot == "ShipBar")
        #expect(run.repositoryPathSnapshot == "/tmp/ShipBar")
        #expect(run.promptSnapshot.contains("Implement run history."))
        #expect(run.status == .prepared)

        context.delete(task)
        try context.save()

        let persisted = try context.fetch(FetchDescriptor<AgentRun>())
        #expect(persisted.map(\.id) == [run.id])
        #expect(persisted.first?.taskTitleSnapshot == "Build Runs")
    }

    @MainActor
    @Test("accepting an agent run completes the run and task")
    func acceptingAgentRunCompletesTask() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let task = ShipTask(title: "Review me")
        context.insert(task)
        let run = AgentRunLifecycle.prepare(task: task, target: .codex, in: context)

        #expect(AgentRunLifecycle.transition(run, to: .handedOff, now: Date(timeIntervalSince1970: 10)))
        #expect(AgentRunLifecycle.transition(run, to: .needsReview, now: Date(timeIntervalSince1970: 15)))
        AgentRunLifecycle.accept(
            run,
            task: task,
            completeTask: true,
            now: Date(timeIntervalSince1970: 20))

        #expect(run.status == .completed)
        #expect(run.finishedAt == Date(timeIntervalSince1970: 20))
        #expect(task.status == .done)
        #expect(task.completedAt == Date(timeIntervalSince1970: 20))
    }

    @MainActor
    @Test("agent run rejects invalid state transitions without mutation")
    func agentRunRejectsInvalidTransitions() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let task = ShipTask(title: "Not finished")
        context.insert(task)
        let run = AgentRunLifecycle.prepare(
            task: task,
            target: .cursor,
            in: context,
            now: Date(timeIntervalSince1970: 10))

        #expect(AgentRunLifecycle.transition(run, to: .completed, now: Date(timeIntervalSince1970: 20)) == false)
        #expect(run.status == .prepared)
        #expect(run.updatedAt == Date(timeIntervalSince1970: 10))
        #expect(run.finishedAt == nil)
    }

    @MainActor
    @Test("requesting changes retains reviewed history and creates a prepared retry")
    func requestingChangesCreatesPreparedRetry() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let task = ShipTask(title: "Try again", prompt: "Fix the review feedback.")
        context.insert(task)
        let reviewed = AgentRunLifecycle.prepare(task: task, target: .claude, in: context)
        #expect(AgentRunLifecycle.transition(reviewed, to: .handedOff))
        #expect(AgentRunLifecycle.transition(reviewed, to: .needsReview))

        let retry = AgentRunLifecycle.requestChanges(
            reviewed,
            task: task,
            in: context,
            now: Date(timeIntervalSince1970: 30))

        #expect(reviewed.status == .canceled)
        #expect(reviewed.resultSummary == "Changes requested")
        #expect(retry?.id != reviewed.id)
        #expect(retry?.status == .prepared)
        #expect(retry?.target == .claude)
        #expect(retry?.promptSnapshot.contains("Fix the review feedback.") == true)
    }

    @MainActor
    @Test("failing an agent run records the actionable error")
    func failingAgentRunRecordsError() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let task = ShipTask(title: "Launch agent")
        context.insert(task)
        let run = AgentRunLifecycle.prepare(task: task, target: .cursor, in: context)

        #expect(AgentRunLifecycle.fail(
            run,
            message: "Repository path is unavailable.",
            now: Date(timeIntervalSince1970: 40)))

        #expect(run.status == .failed)
        #expect(run.errorMessage == "Repository path is unavailable.")
        #expect(run.finishedAt == Date(timeIntervalSince1970: 40))
    }

    @Test("today groups separate now next waiting and completed work")
    func todayGroupsSeparateWorkflowStates() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let nowTask = ShipTask(title: "Now", focusDate: day, focusOrder: 1)
        let nextTask = ShipTask(title: "Next", focusDate: day, focusOrder: 2)
        let waitingTask = ShipTask(title: "Waiting", focusDate: day, focusOrder: 3)
        let done = ShipTask(
            title: "Done",
            status: .done,
            completedAt: day,
            focusDate: day,
            focusOrder: nil)
        let run = AgentRun(
            taskID: waitingTask.id,
            taskTitleSnapshot: waitingTask.title,
            statusRawValue: AgentRunStatus.running.rawValue,
            updatedAt: day)

        let groups = TaskQueries.todayGroups(
            from: [nowTask, nextTask, waitingTask, done],
            runs: [run],
            now: day)

        #expect(groups.now?.id == nowTask.id)
        #expect(groups.next.map(\.id) == [nextTask.id])
        #expect(groups.waiting.map(\.id) == [waitingTask.id])
        #expect(groups.completed.map(\.id) == [done.id])
    }

    @Test("agent run queues prioritize review active and recent work")
    func agentRunQueuesGroupWorkflowStates() {
        let review = AgentRun(
            id: "review",
            taskID: "t1",
            taskTitleSnapshot: "Review",
            statusRawValue: AgentRunStatus.needsReview.rawValue,
            updatedAt: Date(timeIntervalSince1970: 30))
        let active = AgentRun(
            id: "active",
            taskID: "t2",
            taskTitleSnapshot: "Active",
            statusRawValue: AgentRunStatus.running.rawValue,
            updatedAt: Date(timeIntervalSince1970: 20))
        let prepared = AgentRun(
            id: "prepared",
            taskID: "t3",
            taskTitleSnapshot: "Prepared",
            statusRawValue: AgentRunStatus.prepared.rawValue,
            updatedAt: Date(timeIntervalSince1970: 10))
        let recent = AgentRun(
            id: "recent",
            taskID: "t4",
            taskTitleSnapshot: "Recent",
            statusRawValue: AgentRunStatus.completed.rawValue,
            updatedAt: Date(timeIntervalSince1970: 40))

        let queues = AgentRunQueries.queues(from: [recent, prepared, active, review])

        #expect(queues.needsReview.map(\.id) == ["review"])
        #expect(queues.active.map(\.id) == ["active", "prepared"])
        #expect(queues.recent.map(\.id) == ["recent"])
    }

    @Test("command search ranks exact project before fuzzy task")
    func commandSearchRanksExactProjectFirst() {
        let project = Project(id: "p1", name: "ShipBar")
        let task = ShipTask(id: "t1", title: "Polish ShipBar settings")

        let results = ShipBarCommandSearch.results(
            query: "ShipBar",
            tasks: [task],
            projects: [project],
            runs: [])

        #expect(results.first?.id == "project:p1")
        #expect(results.map(\.id).contains("task:t1"))
    }

    @Test("empty command search exposes navigation before recent objects")
    func emptyCommandSearchExposesNavigationFirst() {
        let task = ShipTask(id: "t1", title: "Recent task", updatedAt: Date(timeIntervalSince1970: 20))
        let results = ShipBarCommandSearch.results(query: "", tasks: [task], projects: [], runs: [])

        #expect(results.prefix(5).allSatisfy { $0.kind == .navigation })
        #expect(results.map(\.id).contains("task:t1"))
    }

    @Test("completedAt follows done status")
    func completedAtFollowsDoneStatus() {
        let task = ShipTask(title: "Ship parser")

        #expect(task.completedAt == nil)

        task.applyStatus(.done, now: Date(timeIntervalSince1970: 10))
        #expect(task.completedAt == Date(timeIntervalSince1970: 10))

        task.applyStatus(.todo, now: Date(timeIntervalSince1970: 20))
        #expect(task.completedAt == nil)
    }

    @Test("today queue includes due and undated open tasks")
    func todayQueueIncludesDueAndUndatedOpenTasks() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = startOfToday.addingTimeInterval(-3_600)
        let earlierToday = startOfToday.addingTimeInterval(60)
        let laterToday = startOfToday.addingTimeInterval(20 * 3_600)
        let tomorrow = startOfToday.addingTimeInterval(36 * 3_600)

        let overdue = ShipTask(title: "Overdue", priority: .low, dueDate: yesterday)
        let dueToday = ShipTask(title: "Due Today", priority: .high, dueDate: laterToday)
        let dueEarlierToday = ShipTask(title: "Earlier", priority: .medium, dueDate: earlierToday)
        let later = ShipTask(title: "Later", priority: .high, dueDate: tomorrow)
        let undated = ShipTask(title: "Undated", priority: .high)
        let doneToday = ShipTask(title: "Done", status: .done, priority: .high, dueDate: earlierToday)

        let result = TaskQueries.todayTasks(
            from: [overdue, dueToday, dueEarlierToday, later, undated, doneToday],
            now: now)

        #expect(result.map { $0.title } == ["Overdue", "Earlier", "Due Today", "Undated"])
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

    @Test("normal task queries exclude recoverable Trash")
    func taskQueriesExcludeTrash() {
        let active = ShipTask(title: "Active", isInbox: true)
        let trashed = ShipTask(title: "Trashed", isInbox: true)
        trashed.trashedAt = .now

        #expect(TaskQueries.inboxTasks(from: [active, trashed]).map(\.id) == [active.id])
        #expect(TaskQueries.todayTasks(from: [active, trashed]).map(\.id) == [active.id])
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

    @MainActor
    @Test("default project ids are stable across devices")
    func defaultProjectIDsAreStableAcrossDevices() throws {
        let projects = ShipBarDefaultData.defaultProjects

        #expect(projects.map(\.id) == [
            "default-project.learn-x",
            "default-project.vedit",
            "default-project.technologia",
        ])
    }

    @MainActor
    @Test("local duplicate cleanup merges seeded projects and identical tasks")
    func localDuplicateCleanupMergesSeededProjectsAndIdenticalTasks() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let staleLearnX = Project(id: "random-learn-x", name: "LEARN-X", color: "purple", sortOrder: 7)
        let canonicalLearnX = Project(id: "default-project.learn-x", name: "LEARN-X", color: "purple", sortOrder: 0)
        let staleInboxTask = ShipTask(id: "random-task", title: "Study C language course", isInbox: true)
        let canonicalInboxTask = ShipTask(id: "remote-task", title: "Study C language course", isInbox: true)
        let staleProjectTask = ShipTask(id: "random-project-task", title: "check RAG", isInbox: false, project: staleLearnX)
        let canonicalProjectTask = ShipTask(id: "remote-project-task", title: "check RAG", isInbox: false, project: canonicalLearnX)

        context.insert(staleLearnX)
        context.insert(canonicalLearnX)
        context.insert(staleInboxTask)
        context.insert(canonicalInboxTask)
        context.insert(staleProjectTask)
        context.insert(canonicalProjectTask)
        try context.save()

        let result = ShipBarLocalDuplicateResolver.cleanup(in: context)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())

        #expect(result.deletedProjects == 1)
        #expect(result.deletedTasks == 2)
        #expect(projects.map(\.id) == ["default-project.learn-x"])
        #expect(tasks.map(\.title).sorted() == ["Study C language course", "check RAG"])
        #expect(tasks.first { $0.title == "check RAG" }?.project?.id == "default-project.learn-x")

        let freshContext = ModelContext(container)
        let persistedProjects = try freshContext.fetch(FetchDescriptor<Project>())
        let persistedTasks = try freshContext.fetch(FetchDescriptor<ShipTask>())

        #expect(persistedProjects.map(\.id) == ["default-project.learn-x"])
        #expect(persistedTasks.map(\.title).sorted() == ["Study C language course", "check RAG"])
        #expect(persistedTasks.first { $0.title == "check RAG" }?.project?.id == "default-project.learn-x")
    }

    @MainActor
    @Test("local duplicate cleanup canonicalizes default project ids and merges identical blank projects")
    func localDuplicateCleanupCanonicalizesDefaultIDsAndBlankProjects() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        context.insert(Project(id: "random-learn-x", name: "LEARN-X", color: "purple", sortOrder: 0))
        context.insert(Project(id: "blank-project-a", name: "New Project", sortOrder: 3))
        context.insert(Project(id: "blank-project-b", name: "New Project", sortOrder: 4))
        try context.save()

        let result = ShipBarLocalDuplicateResolver.cleanup(in: context)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<Project>())

        #expect(result.updatedProjects == 1)
        #expect(result.deletedProjects == 1)
        #expect(projects.map(\.id).sorted() == ["blank-project-a", "default-project.learn-x"])
    }

    @MainActor
    @Test("project lifecycle can move tasks to inbox before deleting project")
    func projectLifecycleCanMoveTasksToInboxBeforeDeletingProject() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(id: "project-a", name: "Project A")
        let task = ShipTask(id: "task-a", title: "Keep me", isInbox: false, project: project)

        context.insert(project)
        context.insert(task)
        try context.save()

        ShipBarProjectLifecycle.delete(project, taskHandling: .moveToInbox, in: context)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())
        let tombstones = try context.fetch(FetchDescriptor<ShipBarDeletionTombstone>())

        #expect(projects.isEmpty)
        #expect(tasks.map(\.id) == ["task-a"])
        #expect(tasks.first?.project == nil)
        #expect(tasks.first?.isInbox == true)
        #expect(tombstones.map(\.recordID) == ["project-a"])
        #expect(tombstones.first?.recordKind == ShipBarDeletionKind.project.rawValue)
        #expect(tombstones.first?.taskHandling == ShipBarProjectTaskHandling.moveToInbox.rawValue)
    }

    @MainActor
    @Test("project lifecycle deletes project tasks and records tombstones")
    func projectLifecycleDeletesProjectTasksAndRecordsTombstones() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(id: "project-b", name: "Project B")
        let task = ShipTask(id: "task-b", title: "Remove me", isInbox: false, project: project)

        context.insert(project)
        context.insert(task)
        try context.save()

        ShipBarProjectLifecycle.delete(project, taskHandling: .deleteTasks, in: context)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())
        let tombstones = try context.fetch(FetchDescriptor<ShipBarDeletionTombstone>())

        #expect(projects.isEmpty)
        #expect(tasks.isEmpty)
        #expect(Set(tombstones.map(\.recordID)) == ["project-b", "task-b"])
    }

    @MainActor
    @Test("direct sync applies newer remote edits and remote tombstones")
    func directSyncAppliesNewerRemoteEditsAndRemoteTombstones() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(id: "project-c", name: "Old", updatedAt: Date(timeIntervalSince1970: 10))
        let deletedTask = ShipTask(id: "task-c", title: "Delete remotely", project: project)
        let updatedTask = ShipTask(id: "task-d", title: "Old task", updatedAt: Date(timeIntervalSince1970: 10), project: project)

        context.insert(project)
        context.insert(deletedTask)
        context.insert(updatedTask)
        try context.save()

        ShipBarDirectCloudSync.applyPayload(
            projects: [
                ShipBarDirectCloudSync.ProjectPayload(
                    id: "project-c",
                    name: "New",
                    outcome: "Ship a trusted command center",
                    basePrompt: "Updated base",
                    repoPath: "/tmp/new",
                    color: "green",
                    icon: "folder.fill",
                    sortOrder: 5,
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 20)),
            ],
            tasks: [
                ShipBarDirectCloudSync.TaskPayload(
                    id: "task-d",
                    title: "New task",
                    taskDescription: "Updated description",
                    prompt: "Updated prompt",
                    status: TaskStatus.doing.rawValue,
                    priority: TaskPriority.high.rawValue,
                    type: TaskType.bug.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 20),
                    completedAt: nil,
                    dueDate: nil,
                    isInbox: false,
                    sourceApp: "",
                    sourceURL: "",
                    rawCaptureText: "",
                    projectID: "project-c",
                    projectName: "New"),
            ],
            tombstones: [
                ShipBarDirectCloudSync.TombstonePayload(
                    recordKind: ShipBarDeletionKind.task.rawValue,
                    recordID: "task-c",
                    taskHandling: nil,
                    deletedAt: Date(timeIntervalSince1970: 30)),
            ],
            to: container)

        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())

        #expect(projects.first?.name == "New")
        #expect(projects.first?.outcome == "Ship a trusted command center")
        #expect(projects.first?.basePrompt == "Updated base")
        #expect(tasks.map(\.id) == ["task-d"])
        #expect(tasks.first?.title == "New task")
        #expect(tasks.first?.status == .doing)
        #expect(tasks.first?.priority == .high)
    }

    @Test("direct sync tolerates duplicate model ids and keeps the newest value")
    func directSyncToleratesDuplicateModelIDs() {
        let older = Project(
            id: "default-project.learn-x",
            name: "Old LEARN-X",
            updatedAt: Date(timeIntervalSince1970: 10))
        let newer = Project(
            id: "default-project.learn-x",
            name: "Current LEARN-X",
            updatedAt: Date(timeIntervalSince1970: 20))

        let projects = ShipBarDirectCloudSync.newestValuesByID(
            [older, newer],
            id: \.id,
            updatedAt: \.updatedAt)

        #expect(projects.count == 1)
        #expect(projects["default-project.learn-x"] === newer)
    }

    @MainActor
    @Test("direct sync applies V2 focus and agent run state")
    func directSyncAppliesV2State() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let day = Date(timeIntervalSince1970: 1_720_000_000)

        ShipBarDirectCloudSync.applyPayload(
            projects: [],
            tasks: [
                ShipBarDirectCloudSync.TaskPayload(
                    id: "focused-task",
                    title: "Focused",
                    taskDescription: "",
                    prompt: "",
                    status: TaskStatus.todo.rawValue,
                    priority: TaskPriority.high.rawValue,
                    type: TaskType.feature.rawValue,
                    createdAt: day,
                    updatedAt: day,
                    completedAt: nil,
                    dueDate: nil,
                    focusDate: day,
                    focusOrder: 1,
                    isInbox: false,
                    sourceApp: "",
                    sourceURL: "",
                    rawCaptureText: "",
                    projectID: nil,
                    projectName: nil),
            ],
            runs: [
                ShipBarDirectCloudSync.AgentRunPayload(
                    id: "run-1",
                    taskID: "focused-task",
                    projectID: nil,
                    taskTitleSnapshot: "Focused",
                    projectNameSnapshot: nil,
                    targetRawValue: AgentTarget.codex.rawValue,
                    statusRawValue: AgentRunStatus.needsReview.rawValue,
                    promptSnapshot: "Ship it",
                    repositoryPathSnapshot: "",
                    createdAt: day,
                    updatedAt: day,
                    startedAt: day,
                    finishedAt: nil,
                    resultSummary: "Ready",
                    evidenceURLString: "file:///tmp/evidence.html",
                    errorMessage: "",
                    preparationKey: ""),
            ],
            tombstones: [],
            to: container)

        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())
        let runs = try context.fetch(FetchDescriptor<AgentRun>())
        #expect(tasks.first?.focusDate == day)
        #expect(tasks.first?.focusOrder == 1)
        #expect(runs.first?.taskID == "focused-task")
        #expect(runs.first?.status == .needsReview)
        #expect(runs.first?.resultSummary == "Ready")
    }

    @MainActor
    @Test("direct sync preserves tasks when remote project delete moved them to inbox")
    func directSyncPreservesTasksWhenRemoteProjectDeleteMovedThemToInbox() throws {
        let container = try ShipBarModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let project = Project(id: "project-d", name: "Project D")
        let task = ShipTask(id: "task-e", title: "Keep remotely", isInbox: false, project: project)

        context.insert(project)
        context.insert(task)
        try context.save()

        ShipBarDirectCloudSync.applyPayload(
            projects: [],
            tasks: [
                ShipBarDirectCloudSync.TaskPayload(
                    id: "task-e",
                    title: "Keep remotely",
                    taskDescription: "",
                    prompt: "",
                    status: TaskStatus.todo.rawValue,
                    priority: TaskPriority.medium.rawValue,
                    type: TaskType.idea.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 40),
                    completedAt: nil,
                    dueDate: nil,
                    isInbox: true,
                    sourceApp: "",
                    sourceURL: "",
                    rawCaptureText: "",
                    projectID: nil,
                    projectName: nil),
            ],
            tombstones: [
                ShipBarDirectCloudSync.TombstonePayload(
                    recordKind: ShipBarDeletionKind.project.rawValue,
                    recordID: "project-d",
                    taskHandling: ShipBarProjectTaskHandling.moveToInbox.rawValue,
                    deletedAt: Date(timeIntervalSince1970: 30)),
            ],
            to: container)

        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<ShipTask>())
        let tombstones = try context.fetch(FetchDescriptor<ShipBarDeletionTombstone>())

        #expect(projects.isEmpty)
        #expect(tasks.map(\.id) == ["task-e"])
        #expect(tasks.first?.project == nil)
        #expect(tasks.first?.isInbox == true)
        #expect(Set(tombstones.map(\.recordID)) == ["project-d"])
        #expect(tombstones.first?.taskHandling == ShipBarProjectTaskHandling.moveToInbox.rawValue)
    }

    @Test("destination dock has stable labels and keyboard order")
    func destinationDockContractIsStable() {
        #expect(ShipBarDestination.allCases.map(\.label) == [
            "Today", "Inbox", "Runs", "Projects", "Settings",
        ])
        #expect(ShipBarDestination.allCases.map(\.shortcutNumber) == [1, 2, 3, 4, 5])
    }

    @Test("agent run statuses expose consistent human-readable labels")
    func agentRunStatusDisplayLabels() {
        #expect(AgentRunStatus.prepared.displayLabel == "Prepared")
        #expect(AgentRunStatus.handedOff.displayLabel == "Handed off")
        #expect(AgentRunStatus.running.displayLabel == "Running")
        #expect(AgentRunStatus.needsReview.displayLabel == "Needs review")
        #expect(AgentRunStatus.completed.displayLabel == "Completed")
        #expect(AgentRunStatus.failed.displayLabel == "Failed")
        #expect(AgentRunStatus.canceled.displayLabel == "Canceled")
    }

    @Test("non-project destinations clear hidden project context")
    func nonProjectDestinationsClearHiddenProjectContext() {
        let projectID = "project-1"

        #expect(ShipBarDestination.projects.retainedProjectID(projectID) == projectID)
        for destination in ShipBarDestination.allCases where destination != .projects {
            #expect(destination.retainedProjectID(projectID) == nil)
        }
    }

    @Test("only unscoped capture notifications present the global sheet")
    func onlyUnscopedCaptureNotificationsPresentGlobalSheet() {
        let unscoped = Notification(name: .shipBarOpenCapture)
        let panelScoped = Notification(name: .shipBarOpenCapture, object: NSObject())

        #expect(ShipBarNotificationRouting.shouldPresentGlobalCapture(unscoped))
        #expect(ShipBarNotificationRouting.shouldPresentGlobalCapture(panelScoped) == false)
    }

    @Test("destination badges count only actionable work")
    func destinationBadgesCountActionableWork() {
        let project = Project(name: "ShipBar")
        let focused = ShipTask(title: "Focus", focusDate: .now, focusOrder: 1, project: project)
        let due = ShipTask(title: "Due", dueDate: .now, project: project)
        let inbox = ShipTask(title: "Inbox", isInbox: true)
        let review = AgentRun(
            taskID: focused.id,
            projectID: project.id,
            taskTitleSnapshot: focused.title,
            statusRawValue: AgentRunStatus.needsReview.rawValue)
        let failed = AgentRun(
            taskID: inbox.id,
            taskTitleSnapshot: inbox.title,
            statusRawValue: AgentRunStatus.failed.rawValue)

        let tasks = [focused, due, inbox]
        let runs = [review, failed]
        #expect(ShipBarDestination.today.actionableCount(tasks: tasks, runs: runs) == 2)
        #expect(ShipBarDestination.inbox.actionableCount(tasks: tasks, runs: runs) == 1)
        #expect(ShipBarDestination.runs.actionableCount(tasks: tasks, runs: runs) == 2)
        #expect(ShipBarDestination.projects.actionableCount(tasks: tasks, runs: runs) == nil)
    }
}
