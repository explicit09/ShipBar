import Foundation

struct CaptureDraft: Equatable {
    var title: String
    var prompt: String
    var projectID: String?
    var status: TaskStatus
    var priority: TaskPriority
    var type: TaskType
    var sourceApp: String
    var sourceURL: String
    var rawText: String
}

enum CaptureParser {
    static func parse(_ input: String, projects: [ProjectToken]) -> CaptureDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureDraft(
                title: "",
                prompt: "",
                projectID: nil,
                status: .todo,
                priority: .medium,
                type: .idea,
                sourceApp: "",
                sourceURL: "",
                rawText: "")
        }
        let splitInput = splitPromptAndSource(from: trimmed)
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
                    status: parsed.status,
                    priority: parsed.priority,
                    type: parsed.type,
                    sourceApp: splitInput.sourceApp,
                    sourceURL: splitInput.sourceURL,
                    rawText: trimmed)
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
                status: parsed.status,
                priority: parsed.priority,
                type: parsed.type,
                sourceApp: splitInput.sourceApp,
                sourceURL: splitInput.sourceURL,
                rawText: trimmed)
        }

        return CaptureDraft(
            title: taskInput,
            prompt: splitInput.prompt,
            projectID: nil,
            status: .todo,
            priority: .medium,
            type: .idea,
            sourceApp: splitInput.sourceApp,
            sourceURL: splitInput.sourceURL,
            rawText: trimmed)
    }

    private static func parseMetadata(_ metadata: String, projects: [ProjectToken]) -> ParsedTokens {
        parseLeadingTokens(metadata.split(whereSeparator: \.isWhitespace).map(String.init), projects: projects)
    }

    private static func parseLeadingTokens(_ tokens: [String], projects: [ProjectToken]) -> ParsedTokens {
        var projectID: String?
        var status: TaskStatus = .todo
        var priority: TaskPriority = .medium
        var type: TaskType = .idea
        var consumedCount = 0

        for token in tokens {
            let normalized = ProjectToken.slugify(token)
            if projectID == nil, let project = projects.first(where: { $0.matches(token) }) {
                projectID = project.id
                consumedCount += 1
                continue
            }
            if let parsedStatus = statusToken(normalized) {
                status = parsedStatus
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

        return ParsedTokens(projectID: projectID, status: status, priority: priority, type: type, consumedCount: consumedCount)
    }

    private static func statusToken(_ value: String) -> TaskStatus? {
        switch value {
        case "todo", "to-do", "next": .todo
        case "doing", "in-progress", "inprogress", "progress": .doing
        case "done", "complete", "completed": .done
        default: nil
        }
    }

    private static func priorityToken(_ value: String) -> TaskPriority? {
        switch value {
        case "low": .low
        case "medium", "med": .medium
        case "high": .high
        default: nil
        }
    }

    private static func splitPromptAndSource(from input: String) -> (taskText: String, prompt: String, sourceApp: String, sourceURL: String) {
        let parts = input.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (input, "", "", "") }
        let parsedPrompt = parseSourceMarkers(from: String(parts[1]))
        return (
            String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines),
            parsedPrompt.prompt,
            parsedPrompt.sourceApp,
            parsedPrompt.sourceURL)
    }

    private static func parseSourceMarkers(from prompt: String) -> (prompt: String, sourceApp: String, sourceURL: String) {
        var words = prompt.split(whereSeparator: \.isWhitespace).map(String.init)
        var sourceApp = ""
        var sourceURL = ""

        words.removeAll { word in
            if word.hasPrefix("@source=") {
                sourceApp = String(word.dropFirst("@source=".count))
                return true
            }
            if word.hasPrefix("@url=") {
                sourceURL = String(word.dropFirst("@url=".count))
                return true
            }
            return false
        }

        return (
            words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            sourceApp,
            sourceURL)
    }
}

private struct ParsedTokens {
    let projectID: String?
    let status: TaskStatus
    let priority: TaskPriority
    let type: TaskType
    let consumedCount: Int

    var hasAnyMetadata: Bool {
        self.projectID != nil || self.status != .todo || self.priority != .medium || self.type != .idea || self.consumedCount > 0
    }
}
