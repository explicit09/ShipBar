import Foundation

struct CaptureDraft: Equatable {
    var title: String
    var prompt: String
    var projectID: String?
    var priority: TaskPriority
    var type: TaskType
}

enum CaptureParser {
    static func parse(_ input: String, projects: [ProjectToken]) -> CaptureDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureDraft(title: "", prompt: "", projectID: nil, priority: .medium, type: .idea)
        }
        let splitInput = splitPrompt(from: trimmed)
        let taskInput = splitInput.taskText

        let parts = taskInput.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let metadata = String(parts[0])
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = parseMetadata(metadata, projects: projects)
            if parsed.hasAnyMetadata, !title.isEmpty {
                return CaptureDraft(
                    title: title,
                    prompt: splitInput.prompt,
                    projectID: parsed.projectID,
                    priority: parsed.priority,
                    type: parsed.type)
            }
        }

        let tokens = taskInput.split(whereSeparator: \.isWhitespace).map(String.init)
        let parsed = parseLeadingTokens(tokens, projects: projects)
        if parsed.consumedCount > 0, parsed.consumedCount < tokens.count {
            let title = tokens.dropFirst(parsed.consumedCount).joined(separator: " ")
            return CaptureDraft(
                title: title,
                prompt: splitInput.prompt,
                projectID: parsed.projectID,
                priority: parsed.priority,
                type: parsed.type)
        }

        return CaptureDraft(title: taskInput, prompt: splitInput.prompt, projectID: nil, priority: .medium, type: .idea)
    }

    private static func parseMetadata(_ metadata: String, projects: [ProjectToken]) -> ParsedTokens {
        parseLeadingTokens(metadata.split(whereSeparator: \.isWhitespace).map(String.init), projects: projects)
    }

    private static func parseLeadingTokens(_ tokens: [String], projects: [ProjectToken]) -> ParsedTokens {
        var projectID: String?
        var priority: TaskPriority = .medium
        var type: TaskType = .idea
        var consumedCount = 0

        for token in tokens {
            let normalized = ProjectToken.slugify(token)
            if projectID == nil, let project = projects.first(where: { $0.slug == normalized || $0.name.lowercased() == token.lowercased() }) {
                projectID = project.id
                consumedCount += 1
                continue
            }
            if let parsedPriority = priorityToken(normalized) {
                priority = parsedPriority
                consumedCount += 1
                continue
            }
            if let parsedType = TaskType(rawValue: normalized) {
                type = parsedType
                consumedCount += 1
                continue
            }
            break
        }

        return ParsedTokens(projectID: projectID, priority: priority, type: type, consumedCount: consumedCount)
    }

    private static func priorityToken(_ value: String) -> TaskPriority? {
        switch value {
        case "low": .low
        case "medium", "med": .medium
        case "high": .high
        default: nil
        }
    }

    private static func splitPrompt(from input: String) -> (taskText: String, prompt: String) {
        let parts = input.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (input, "") }
        return (
            String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct ParsedTokens {
    let projectID: String?
    let priority: TaskPriority
    let type: TaskType
    let consumedCount: Int

    var hasAnyMetadata: Bool {
        self.projectID != nil || self.priority != .medium || self.type != .idea || self.consumedCount > 0
    }
}
