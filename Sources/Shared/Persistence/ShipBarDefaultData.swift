import Foundation
import SwiftData

struct ShipBarDefaultProjectTemplate: Equatable {
    let id: String
    let name: String
    let color: String
    let basePrompt: String
    let sortOrder: Int
}

enum ShipBarDefaultData {
    static let defaultProjects: [ShipBarDefaultProjectTemplate] = [
        ShipBarDefaultProjectTemplate(
            id: "default-project.learn-x",
            name: "LEARN-X",
            color: "purple",
            basePrompt: "You are working in the LEARN-X repository. Keep learning flows concise and useful.",
            sortOrder: 0),
        ShipBarDefaultProjectTemplate(
            id: "default-project.vedit",
            name: "vedit",
            color: "green",
            basePrompt: "You are working in the vedit repository. Build robust, maintainable video editing workflows.",
            sortOrder: 1),
        ShipBarDefaultProjectTemplate(
            id: "default-project.technologia",
            name: "Technologia",
            color: "orange",
            basePrompt: "You are working on Technologia. Keep writing clear, specific, and shippable.",
            sortOrder: 2),
    ]

    static let defaultProjectIDsByName = Dictionary(
        uniqueKeysWithValues: Self.defaultProjects.map { (Self.normalizedName($0.name), $0.id) })

    @MainActor
    static func seedProjectsIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existing.isEmpty else { return }

        for template in Self.defaultProjects {
            context.insert(Project(
                id: template.id,
                name: template.name,
                basePrompt: template.basePrompt,
                color: template.color,
                sortOrder: template.sortOrder))
        }
        ShipBarPersistence.save(context, operation: "Seed default projects")
    }

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
