import SwiftUI

enum ShipBarSection: String, CaseIterable, Identifiable {
    case buildBar
    case projects
    case tasks
    case prompts
    case agents
    case settings

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .buildBar: "BuildBar"
        case .projects: "Projects"
        case .tasks: "Tasks"
        case .prompts: "Prompts"
        case .agents: "Agents"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .buildBar: "checkmark.circle"
        case .projects: "folder"
        case .tasks: "list.bullet"
        case .prompts: "sparkles"
        case .agents: "cpu"
        case .settings: "gearshape"
        }
    }

    var progressTint: Color {
        switch self {
        case .buildBar: ShipBarStyle.accent
        case .projects: ShipBarStyle.promptGreen
        case .tasks: Color.orange
        case .prompts: Color.blue
        case .agents: Color.purple
        case .settings: Color.secondary.opacity(0.45)
        }
    }
}
