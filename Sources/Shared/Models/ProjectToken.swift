import Foundation

struct ProjectToken: Equatable {
    let id: String
    let name: String

    var slug: String {
        Self.slugify(self.name)
    }

    func matches(_ value: String) -> Bool {
        let normalized = Self.slugify(value)
        return self.slug == normalized || Self.compact(self.slug) == Self.compact(normalized)
    }

    static func slugify(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func compact(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "")
    }
}
