import Foundation
import SwiftData

@Model
final class ShipTask {
    var id: String = UUID().uuidString
    var title: String = ""
    var taskDescription: String = ""
    var prompt: String = ""
    var status: TaskStatus = TaskStatus.todo
    var priority: TaskPriority = TaskPriority.medium
    var type: TaskType = TaskType.idea
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var dueDate: Date?
    var isInbox: Bool = false
    var sourceApp: String = ""
    var sourceURL: String = ""
    var rawCaptureText: String = ""
    var sourceCaptureID: String = ""
    var lastAgentTargetRawValue: String = ""
    var lastAgentHandoffAt: Date?
    var agentHandoffCount: Int = 0
    var focusDate: Date?
    var focusOrder: Int?
    var project: Project?

    init(
        id: String = UUID().uuidString,
        title: String,
        taskDescription: String = "",
        prompt: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        type: TaskType = .idea,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        isInbox: Bool = false,
        sourceApp: String = "",
        sourceURL: String = "",
        rawCaptureText: String = "",
        sourceCaptureID: String = "",
        lastAgentTargetRawValue: String = "",
        lastAgentHandoffAt: Date? = nil,
        agentHandoffCount: Int = 0,
        focusDate: Date? = nil,
        focusOrder: Int? = nil,
        project: Project? = nil)
    {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.prompt = prompt
        self.status = status
        self.priority = priority
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.isInbox = isInbox
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.rawCaptureText = rawCaptureText
        self.sourceCaptureID = sourceCaptureID
        self.lastAgentTargetRawValue = lastAgentTargetRawValue
        self.lastAgentHandoffAt = lastAgentHandoffAt
        self.agentHandoffCount = agentHandoffCount
        self.focusDate = focusDate
        self.focusOrder = focusOrder
        self.project = project
    }

    var hasPrompt: Bool {
        !self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var lastAgentTarget: AgentTarget? {
        AgentTarget(rawValue: self.lastAgentTargetRawValue)
    }

    var isFocusedToday: Bool {
        guard let focusDate else { return false }
        return Calendar.current.isDateInToday(focusDate)
    }

    func applyStatus(_ newStatus: TaskStatus, now: Date = .now) {
        self.status = newStatus
        self.updatedAt = now
        self.completedAt = newStatus == .done ? now : nil
    }

    func triage(
        project: Project?,
        status: TaskStatus = .todo,
        priority: TaskPriority? = nil,
        type: TaskType? = nil,
        now: Date = .now)
    {
        self.project = project
        self.isInbox = false
        if let priority {
            self.priority = priority
        }
        if let type {
            self.type = type
        }
        self.applyStatus(status, now: now)
    }

    func beginAgentHandoff(to target: AgentTarget, now: Date = .now) -> AgentWorkflowAction {
        if self.status != .done {
            self.applyStatus(.doing, now: now)
        }
        self.lastAgentTargetRawValue = target.rawValue
        self.lastAgentHandoffAt = now
        self.agentHandoffCount += 1
        return AgentWorkflowAction.make(for: target, task: self)
    }
}
