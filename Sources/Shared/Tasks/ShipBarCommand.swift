import Foundation

enum ShipBarCommandKind: Int, Equatable {
    case navigation = 0
    case project = 1
    case task = 2
    case run = 3
}

struct ShipBarCommandResult: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let kind: ShipBarCommandKind
    let score: Int
}

enum ShipBarCommandSearch {
    private static let navigation: [ShipBarCommandResult] = [
        .init(id: "nav:today", title: "Today", subtitle: "Daily command center", systemImage: "checkmark.circle", kind: .navigation, score: 0),
        .init(id: "nav:inbox", title: "Inbox", subtitle: "Triage captured work", systemImage: "tray", kind: .navigation, score: 0),
        .init(id: "nav:runs", title: "Runs", subtitle: "Review agent work", systemImage: "paperplane", kind: .navigation, score: 0),
        .init(id: "nav:projects", title: "Projects", subtitle: "Open a workspace", systemImage: "folder", kind: .navigation, score: 0),
        .init(id: "nav:settings", title: "Settings", subtitle: "Sync, capture, and diagnostics", systemImage: "gearshape", kind: .navigation, score: 0),
    ]

    static func results(
        query: String,
        tasks: [ShipTask],
        projects: [Project],
        runs: [AgentRun]) -> [ShipBarCommandResult]
    {
        let objectResults = projects.map {
            ShipBarCommandResult(
                id: "project:\($0.id)", title: $0.name, subtitle: "Project",
                systemImage: "folder.fill", kind: .project, score: 0)
        } + tasks.map {
            ShipBarCommandResult(
                id: "task:\($0.id)", title: $0.title,
                subtitle: $0.project?.name ?? "Inbox", systemImage: "circle",
                kind: .task, score: 0)
        } + runs.map {
            ShipBarCommandResult(
                id: "run:\($0.id)", title: $0.taskTitleSnapshot,
                subtitle: $0.target?.label ?? "Agent run", systemImage: "paperplane.fill",
                kind: .run, score: 0)
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let recentObjects = objectResults.sorted { lhs, rhs in
                if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return Array((Self.navigation + recentObjects).prefix(12))
        }

        let normalizedQuery = Self.normalize(trimmed)
        return (Self.navigation + objectResults)
            .compactMap { result -> ShipBarCommandResult? in
                guard let score = Self.matchScore(query: normalizedQuery, candidate: Self.normalize(result.title)) else {
                    return nil
                }
                return ShipBarCommandResult(
                    id: result.id,
                    title: result.title,
                    subtitle: result.subtitle,
                    systemImage: result.systemImage,
                    kind: result.kind,
                    score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(12)
            .map { $0 }
    }

    private static func matchScore(query: String, candidate: String) -> Int? {
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 10 }
        if candidate.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 20 }
        if candidate.contains(query) { return 30 }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
