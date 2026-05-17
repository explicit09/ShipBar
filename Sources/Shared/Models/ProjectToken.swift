import Foundation

struct ProjectToken: Equatable {
    let id: String
    let name: String

    var slug: String {
        Self.slugify(self.name)
    }

    static func slugify(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}
