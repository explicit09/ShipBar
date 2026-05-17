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
        self.project = project
    }

    var hasPrompt: Bool {
        !self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyStatus(_ newStatus: TaskStatus, now: Date = .now) {
        self.status = newStatus
        self.updatedAt = now
        self.completedAt = newStatus == .done ? now : nil
    }
}
