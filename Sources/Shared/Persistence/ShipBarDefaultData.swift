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

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

enum ShipBarLegacyMockCleanup {
    private static let chatGPTQATaskIDs: Set<String> = [
        "053C4BF1-2042-4B20-94B5-DB456256E53F",
    ]

    @MainActor
    @discardableResult
    static func cleanup(in context: ModelContext) -> Int {
        let runs = (try? context.fetch(FetchDescriptor<AgentRun>())) ?? []
        let matches = runs.filter {
            Self.chatGPTQATaskIDs.contains($0.taskID) ||
                $0.taskTitleSnapshot == "ChatGPT Action verified end to end"
        }
        for run in matches {
            ShipBarDeletionLog.record(.run, id: run.id, in: context)
            context.delete(run)
        }
        if !matches.isEmpty {
            ShipBarPersistence.save(context, operation: "Remove legacy QA runs", notifiesSync: false)
        }
        return matches.count
    }
}
