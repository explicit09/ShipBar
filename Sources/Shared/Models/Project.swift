import Foundation
import SwiftData

@Model
final class Project {
    var id: String = UUID().uuidString
    var name: String = ""
    var outcome: String = ""
    var basePrompt: String = ""
    var repoPath: String = ""
    var color: String = "blue"
    var icon: String = "square.stack.3d.up"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var trashedAt: Date?
    var lastRemoteCommandID: String = ""
    @Relationship(deleteRule: .cascade, inverse: \ShipTask.project)
    var tasks: [ShipTask]?

    init(
        id: String = UUID().uuidString,
        name: String,
        outcome: String = "",
        basePrompt: String = "",
        repoPath: String = "",
        color: String = "blue",
        icon: String = "square.stack.3d.up",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        revision: Int = 0,
        trashedAt: Date? = nil,
        lastRemoteCommandID: String = "",
        tasks: [ShipTask] = [])
    {
        self.id = id
        self.name = name
        self.outcome = outcome
        self.basePrompt = basePrompt
        self.repoPath = repoPath
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.trashedAt = trashedAt
        self.lastRemoteCommandID = lastRemoteCommandID
        self.tasks = tasks
    }

    var token: ProjectToken {
        ProjectToken(id: self.id, name: self.name)
    }
}
