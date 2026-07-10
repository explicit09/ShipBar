import Foundation
import SwiftData

enum AgentRunLifecycle {
    private static let allowedTransitions: [AgentRunStatus: Set<AgentRunStatus>] = [
        .prepared: [.handedOff, .failed, .canceled],
        .handedOff: [.running, .needsReview, .failed, .canceled],
        .running: [.needsReview, .failed, .canceled],
        .needsReview: [.completed, .failed, .canceled],
        .completed: [],
        .failed: [],
        .canceled: [],
    ]

    @MainActor
    static func prepare(
        task: ShipTask,
        target: AgentTarget,
        in context: ModelContext,
        now: Date = .now) -> AgentRun
    {
        let action = AgentWorkflowAction.make(for: target, task: task)
        let run = AgentRun(
            taskID: task.id,
            projectID: task.project?.id,
            taskTitleSnapshot: task.title,
            projectNameSnapshot: task.project?.name,
            targetRawValue: target.rawValue,
            statusRawValue: AgentRunStatus.prepared.rawValue,
            promptSnapshot: action.clipboardText,
            repositoryPathSnapshot: action.repoPath,
            createdAt: now,
            updatedAt: now)
        context.insert(run)
        return run
    }

    @MainActor
    @discardableResult
    static func transition(
        _ run: AgentRun,
        to nextStatus: AgentRunStatus,
        now: Date = .now) -> Bool
    {
        guard Self.allowedTransitions[run.status, default: []].contains(nextStatus) else {
            return false
        }

        run.status = nextStatus
        run.updatedAt = now
        if nextStatus == .running {
            run.startedAt = run.startedAt ?? now
        }
        if [.completed, .failed, .canceled].contains(nextStatus) {
            run.finishedAt = now
        }
        return true
    }

    @MainActor
    static func accept(
        _ run: AgentRun,
        task: ShipTask?,
        completeTask: Bool,
        now: Date = .now)
    {
        guard Self.transition(run, to: .completed, now: now) else { return }
        if completeTask {
            task?.applyStatus(.done, now: now)
        }
    }

    @MainActor
    static func requestChanges(
        _ run: AgentRun,
        task: ShipTask,
        in context: ModelContext,
        now: Date = .now) -> AgentRun?
    {
        guard let target = run.target,
              Self.transition(run, to: .canceled, now: now)
        else { return nil }

        run.resultSummary = "Changes requested"
        return Self.prepare(task: task, target: target, in: context, now: now)
    }

    @MainActor
    @discardableResult
    static func fail(
        _ run: AgentRun,
        message: String,
        now: Date = .now) -> Bool
    {
        guard Self.transition(run, to: .failed, now: now) else { return false }
        run.errorMessage = message
        return true
    }
}
