import Foundation

enum TaskType: String, Codable, CaseIterable, Identifiable {
    case feature
    case bug
    case chore
    case idea

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .feature: "Feature"
        case .bug: "Bug"
        case .chore: "Chore"
        case .idea: "Idea"
        }
    }
}
