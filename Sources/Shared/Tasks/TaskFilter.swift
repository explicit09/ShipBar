import Foundation

struct TaskFilter: Equatable {
    var status: TaskStatus?
    var priority: TaskPriority?
    var type: TaskType?
    var projectID: String?
    var inboxOnly: Bool
    var promptReadyOnly: Bool
    var includeDone: Bool

    init(
        status: TaskStatus? = nil,
        priority: TaskPriority? = nil,
        type: TaskType? = nil,
        projectID: String? = nil,
        inboxOnly: Bool = false,
        promptReadyOnly: Bool = false,
        includeDone: Bool = false)
    {
        self.status = status
        self.priority = priority
        self.type = type
        self.projectID = projectID
        self.inboxOnly = inboxOnly
        self.promptReadyOnly = promptReadyOnly
        self.includeDone = includeDone
    }

    static let open = TaskFilter()
    static let inbox = TaskFilter(inboxOnly: true)
    static let promptReady = TaskFilter(promptReadyOnly: true)
}
