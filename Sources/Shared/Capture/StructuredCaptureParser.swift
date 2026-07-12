import Foundation

enum StructuredCaptureParser {
    private static let heading = "# ShipBar Task"

    private enum Section: String {
        case description = "Description:"
        case acceptanceCriteria = "Acceptance Criteria:"
        case agentPrompt = "Agent Prompt:"
    }

    static func parse(_ input: String, projects: [ProjectToken]) -> CaptureDraft? {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = normalized.components(separatedBy: "\n")[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == Self.heading else { return nil }
        lines = lines.dropFirst()

        var title = ""
        var projectID: String?
        var priority = TaskPriority.medium
        var type = TaskType.idea
        var description: [String] = []
        var criteria: [String] = []
        var prompt: [String] = []
        var section: Section?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let newSection = Section(rawValue: line) {
                section = newSection
                continue
            }
            switch section {
            case nil:
                if let value = Self.fieldValue("Title", from: line) {
                    title = value
                } else if let value = Self.fieldValue("Project", from: line) {
                    projectID = projects.first { $0.matches(value) }?.id
                } else if let value = Self.fieldValue("Priority", from: line) {
                    priority = Self.priority(from: value) ?? priority
                } else if let value = Self.fieldValue("Type", from: line) {
                    type = Self.type(from: value) ?? type
                }
            case .description:
                description.append(rawLine)
            case .acceptanceCriteria:
                criteria.append(rawLine)
            case .agentPrompt:
                prompt.append(rawLine)
            }
        }

        guard !title.isEmpty else { return nil }

        var descriptionText = Self.joined(description)
        let criteriaText = Self.joined(criteria)
        if !criteriaText.isEmpty {
            descriptionText = descriptionText.isEmpty
                ? "Acceptance Criteria:\n\(criteriaText)"
                : "\(descriptionText)\n\nAcceptance Criteria:\n\(criteriaText)"
        }

        return CaptureDraft(
            title: title,
            prompt: Self.joined(prompt),
            projectID: projectID,
            status: .todo,
            priority: priority,
            type: type,
            dueDate: nil,
            sourceApp: "",
            sourceURL: "",
            rawText: normalized,
            taskDescription: descriptionText)
    }

    private static func fieldValue(_ field: String, from line: String) -> String? {
        guard line.hasPrefix("\(field):") else { return nil }
        return String(line.dropFirst(field.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    private static func joined(_ lines: [String]) -> String {
        lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func priority(from value: String) -> TaskPriority? {
        switch value.lowercased() {
        case "low", "p3": .low
        case "medium", "med", "p2": .medium
        case "high", "urgent", "p1": .high
        default: nil
        }
    }

    private static func type(from value: String) -> TaskType? {
        let normalized = value.lowercased()
        switch normalized {
        case "feature", "feat": return .feature
        case "bug", "fix", "bugfix": return .bug
        case "chore", "cleanup": return .chore
        case "idea", "note": return .idea
        default: return TaskType(rawValue: normalized)
        }
    }
}
