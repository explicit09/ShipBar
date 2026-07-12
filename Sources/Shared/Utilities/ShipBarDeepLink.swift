import Foundation

enum ShipBarDeepLink: Equatable {
    case inbox
    case today
    case prepareTask(id: String)

    static let scheme = "shipbar"

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host else { return nil }
        switch host {
        case "inbox":
            self = .inbox
        case "today":
            self = .today
        case "task":
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, parts[1] == "prepare", !parts[0].isEmpty else { return nil }
            self = .prepareTask(id: parts[0])
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .inbox: URL(string: "\(Self.scheme)://inbox")!
        case .today: URL(string: "\(Self.scheme)://today")!
        case .prepareTask(let id): URL(string: "\(Self.scheme)://task/\(id)/prepare")!
        }
    }
}
