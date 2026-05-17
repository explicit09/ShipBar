import Foundation
import SwiftData

@Model
final class Project {
    var id: String = UUID().uuidString
    var name: String = ""
    var color: String = "blue"
    var icon: String = "square.stack.3d.up"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ShipTask.project)
    var tasks: [ShipTask]?

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        icon: String = "square.stack.3d.up",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tasks: [ShipTask] = [])
    {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = tasks
    }

    var token: ProjectToken {
        ProjectToken(id: self.id, name: self.name)
    }
}
