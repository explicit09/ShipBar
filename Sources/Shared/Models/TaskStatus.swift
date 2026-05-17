import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .todo: "Todo"
        case .doing: "Doing"
        case .done: "Done"
        }
    }
}
