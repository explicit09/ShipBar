import Foundation

struct CaptureDraft: Equatable {
    var title: String
    var prompt: String
    var projectID: String?
    var status: TaskStatus
    var priority: TaskPriority
    var type: TaskType
    var dueDate: Date?
    var sourceApp: String
    var sourceURL: String
    var rawText: String
    var taskDescription: String = ""
    var sourceCaptureID: String = ""
}

enum CaptureParser {
    static func parse(_ input: String, projects: [ProjectToken], now: Date = .now) -> CaptureDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureDraft(
                title: "",
                prompt: "",
                projectID: nil,
                status: .todo,
                priority: .medium,
                type: .idea,
                dueDate: nil,
                sourceApp: "",
                sourceURL: "",
                rawText: "")
        }
        let splitInput = splitPromptAndSource(from: trimmed)
        let taskInput = splitInput.taskText
        let prompt = splitInput.prompt

        let parts = taskInput.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let metadata = String(parts[0])
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = parseMetadata(metadata, projects: projects, now: now)
            if parsed.hasAnyMetadata, !title.isEmpty {
                return CaptureDraft(
                    title: title,
                    prompt: prompt,
                    projectID: parsed.projectID,
                    status: parsed.status,
                    priority: parsed.priority,
                    type: parsed.type,
                    dueDate: parsed.dueDate,
                    sourceApp: splitInput.sourceApp,
                    sourceURL: splitInput.sourceURL,
                    rawText: trimmed)
            }
        }

        let tokens = taskInput.split(whereSeparator: \.isWhitespace).map(String.init)
        let parsed = parseLeadingTokens(tokens, projects: projects, now: now)
        if parsed.consumedCount > 0, parsed.consumedCount < tokens.count {
            let title = tokens.dropFirst(parsed.consumedCount).joined(separator: " ")
            return CaptureDraft(
                title: title,
                prompt: prompt,
                projectID: parsed.projectID,
                status: parsed.status,
                priority: parsed.priority,
                type: parsed.type,
                dueDate: parsed.dueDate,
                sourceApp: splitInput.sourceApp,
                sourceURL: splitInput.sourceURL,
                rawText: trimmed)
        }

        return CaptureDraft(
            title: taskInput,
            prompt: prompt,
            projectID: nil,
            status: .todo,
            priority: .medium,
            type: .idea,
            dueDate: nil,
            sourceApp: splitInput.sourceApp,
            sourceURL: splitInput.sourceURL,
            rawText: trimmed)
    }

    private static func parseMetadata(_ metadata: String, projects: [ProjectToken], now: Date) -> ParsedTokens {
        parseLeadingTokens(metadata.split(whereSeparator: \.isWhitespace).map(String.init), projects: projects, now: now)
    }

    private static func parseLeadingTokens(_ tokens: [String], projects: [ProjectToken], now: Date) -> ParsedTokens {
        var projectID: String?
        var status: TaskStatus = .todo
        var priority: TaskPriority = .medium
        var type: TaskType = .idea
        var dueDate: Date?
        var consumedCount = 0

        for token in tokens {
            let normalized = normalizedToken(token)
            if projectID == nil, let project = projects.first(where: { $0.matches(normalized) }) {
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
            if let parsedType = typeToken(normalized) {
                type = parsedType
                consumedCount += 1
                continue
            }
            if dueDate == nil, let parsedDate = dateToken(normalized, now: now) {
                dueDate = parsedDate
                consumedCount += 1
                continue
            }
            break
        }

        return ParsedTokens(
            projectID: projectID,
            status: status,
            priority: priority,
            type: type,
            dueDate: dueDate,
            consumedCount: consumedCount)
    }

    private static func dateToken(_ value: String, now: Date) -> Date? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfDayOffset: TimeInterval = 24 * 3_600 - 1
        switch value {
        case "today":
            return startOfToday.addingTimeInterval(endOfDayOffset)
        case "tomorrow", "tmrw", "tom":
            return startOfToday.addingTimeInterval(24 * 3_600 + endOfDayOffset)
        case "weekend":
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilSaturday: Int = {
                if weekday == 7 || weekday == 1 { return 0 }
                return (7 - weekday + 7) % 7
            }()
            return calendar.date(byAdding: .day, value: daysUntilSaturday, to: startOfToday)?
                .addingTimeInterval(endOfDayOffset)
        case "monday", "mon":
            return nextWeekday(2, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "tuesday", "tue", "tues":
            return nextWeekday(3, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "wednesday", "wed":
            return nextWeekday(4, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "thursday", "thu", "thur", "thurs":
            return nextWeekday(5, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "friday", "fri":
            return nextWeekday(6, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "saturday", "sat":
            return nextWeekday(7, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        case "sunday", "sun":
            return nextWeekday(1, from: now, calendar: calendar).addingTimeInterval(endOfDayOffset)
        default:
            return nil
        }
    }

    private static func nextWeekday(_ target: Int, from now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        var diff = target - weekday
        if diff <= 0 { diff += 7 }
        return calendar.date(byAdding: .day, value: diff, to: startOfToday) ?? startOfToday
    }

    private static func statusToken(_ value: String) -> TaskStatus? {
        switch value {
        case "todo", "to-do", "next": .todo
        case "doing", "in-progress", "inprogress", "progress", "wip": .doing
        case "done", "complete", "completed": .done
        default: nil
        }
    }

    private static func priorityToken(_ value: String) -> TaskPriority? {
        switch value {
        case "low", "p3": .low
        case "medium", "med", "p2": .medium
        case "high", "urgent", "p1", "!": .high
        default: nil
        }
    }

    private static func typeToken(_ value: String) -> TaskType? {
        switch value {
        case "feature", "feat": .feature
        case "bug", "fix", "bugfix": .bug
        case "chore", "cleanup": .chore
        case "idea", "note": .idea
        default: TaskType(rawValue: value)
        }
    }

    private static func splitPromptAndSource(from input: String) -> (taskText: String, prompt: String, sourceApp: String, sourceURL: String) {
        let parts = input.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            let lines = input
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count > 1 else { return (input, "", "", "") }
            let prompt = lines.dropFirst().joined(separator: "\n")
            let parsedPrompt = parseSourceMarkers(from: prompt)
            return (
                lines[0],
                parsedPrompt.prompt,
                parsedPrompt.sourceApp,
                parsedPrompt.sourceURL)
        }
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

    private static func normalizedToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "!" {
            return trimmed
        }
        return ProjectToken.slugify(String(trimmed.drop { character in
            character == "#" || character == "@"
        }))
    }
}

private struct ParsedTokens {
    let projectID: String?
    let status: TaskStatus
    let priority: TaskPriority
    let type: TaskType
    let dueDate: Date?
    let consumedCount: Int

    var hasAnyMetadata: Bool {
        self.projectID != nil
            || self.status != .todo
            || self.priority != .medium
            || self.type != .idea
            || self.dueDate != nil
            || self.consumedCount > 0
    }
}
