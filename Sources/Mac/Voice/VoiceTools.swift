import AppKit
import Foundation
import SwiftData

enum VoiceTool: String, CaseIterable {
    // Function tools exposed to the Realtime model. Keep this list narrow:
    // every case below can mutate local user data or inspect task state.
    case createTask = "create_task"
    case updateTask = "update_task"
    case markDone = "mark_done"
    case deleteTask = "delete_task"
    case handoffToAgent = "handoff_to_agent"
    case openApp = "open_app"
    case listToday = "list_today"
    case listInbox = "list_inbox"
    case listProjects = "list_projects"

    var isDestructive: Bool {
        // Mirrors the prompt contract in VoiceSession. The model should ask
        // before these, but the executor also keeps local guardrails.
        switch self {
        case .deleteTask, .handoffToAgent, .openApp:
            true
        case .createTask, .updateTask, .markDone, .listToday, .listInbox, .listProjects:
            false
        }
    }

    var schema: [String: Any] {
        switch self {
        case .createTask:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Create a new task in ShipBar. Use when the user asks you to add, capture, or write down a task.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Short task title."],
                        "project_name": ["type": ["string", "null"], "description": "Project name to assign. If null, the task goes to Inbox."],
                        "priority": ["type": "string", "enum": ["high", "medium", "low"], "description": "Defaults to medium."],
                        "type": ["type": "string", "enum": ["idea", "bug", "feature", "chore"], "description": "Defaults to idea."],
                        "prompt": ["type": "string", "description": "Optional agent prompt for this task."],
                    ],
                    "required": ["title"],
                ],
            ]
        case .updateTask:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Update fields on an existing task by title or by id. Match by title is case-insensitive substring.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "match_title": ["type": ["string", "null"]],
                        "task_id": ["type": ["string", "null"]],
                        "new_title": ["type": ["string", "null"]],
                        "project_name": ["type": ["string", "null"]],
                        "priority": ["type": ["string", "null"], "description": "high, medium, or low"],
                        "type": ["type": ["string", "null"], "description": "idea, bug, feature, or chore"],
                        "status": ["type": ["string", "null"], "description": "todo, doing, or done"],
                    ],
                ],
            ]
        case .markDone:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Mark a task as done. Match by id or by title substring.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "match_title": ["type": ["string", "null"]],
                        "task_id": ["type": ["string", "null"]],
                    ],
                ],
            ]
        case .deleteTask:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Permanently delete tasks. Destructive — caller must confirm verbally first. Use task_id or match_title for a single task; set all=true to delete every task; set completed_only=true to delete only finished tasks. Combine all=true with project_name to delete every task in one project.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "match_title": ["type": ["string", "null"]],
                        "task_id": ["type": ["string", "null"]],
                        "all": ["type": ["boolean", "null"], "description": "If true, delete many tasks at once (filtered by completed_only and project_name)."],
                        "completed_only": ["type": ["boolean", "null"], "description": "If true with all=true, only delete tasks already marked done."],
                        "project_name": ["type": ["string", "null"], "description": "If set with all=true, only delete tasks in this project."],
                    ],
                ],
            ]
        case .handoffToAgent:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Hand a task off to an AI coding agent. Copies the prompt to the clipboard and launches the agent. Destructive — caller must confirm verbally first.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "match_title": ["type": ["string", "null"]],
                        "task_id": ["type": ["string", "null"]],
                        "target": ["type": "string", "enum": ["claude", "codex", "cursor"]],
                    ],
                    "required": ["target"],
                ],
            ]
        case .openApp:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "Open a macOS application by name. Destructive — caller must confirm verbally first.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "app_name": ["type": "string", "description": "Application name, e.g. 'Xcode', 'Cursor', 'Terminal'."],
                    ],
                    "required": ["app_name"],
                ],
            ]
        case .listToday:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "List today's open tasks (titles + projects + priorities).",
                "parameters": ["type": "object", "properties": [:]],
            ]
        case .listInbox:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "List untriaged inbox tasks.",
                "parameters": ["type": "object", "properties": [:]],
            ]
        case .listProjects:
            [
                "type": "function",
                "name": self.rawValue,
                "description": "List all projects with open task counts.",
                "parameters": ["type": "object", "properties": [:]],
            ]
        }
    }

    static var allSchemas: [[String: Any]] {
        Self.allCases.map(\.schema)
    }
}

@MainActor
final class VoiceToolExecutor {
    // Executes model-requested tools against local app state. This is deliberately
    // synchronous and local so the Realtime session can receive quick tool results.
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let blockedApps: Set<String> = [
        // Voice-triggered app launch should never open high-impact system tools.
        "System Settings", "System Preferences", "Keychain Access",
        "Disk Utility", "Terminal", "Activity Monitor",
    ]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
    }

    func execute(tool: VoiceTool, arguments: [String: Any]) -> String {
        switch tool {
        case .createTask:
            return self.createTask(arguments)
        case .updateTask:
            return self.updateTask(arguments)
        case .markDone:
            return self.markDone(arguments)
        case .deleteTask:
            return self.deleteTask(arguments)
        case .handoffToAgent:
            return self.handoffToAgent(arguments)
        case .openApp:
            return self.openApp(arguments)
        case .listToday:
            return self.listToday()
        case .listInbox:
            return self.listInbox()
        case .listProjects:
            return self.listProjects()
        }
    }

    private func createTask(_ args: [String: Any]) -> String {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return self.error("title is required")
        }
        let projects = self.fetchProjects()
        let project = self.matchProject(named: args["project_name"] as? String, in: projects)
        let priority = self.parsePriority(args["priority"] as? String) ?? .medium
        let type = self.parseType(args["type"] as? String) ?? .idea
        let prompt = args["prompt"] as? String ?? ""

        let task = ShipTask(
            title: title,
            prompt: prompt,
            priority: priority,
            type: type,
            isInbox: project == nil,
            project: project)
        self.modelContext.insert(task)
        try? self.modelContext.save()

        return self.success([
            "created_task_id": task.id,
            "title": task.title,
            "project": project?.name ?? "Inbox",
        ])
    }

    private func updateTask(_ args: [String: Any]) -> String {
        guard let task = self.findTask(args) else { return self.error("no matching task") }
        if let newTitle = args["new_title"] as? String, !newTitle.isEmpty {
            task.title = newTitle
        }
        if let projectName = args["project_name"] as? String {
            let projects = self.fetchProjects()
            task.project = self.matchProject(named: projectName, in: projects)
            task.isInbox = task.project == nil
        }
        if let priority = self.parsePriority(args["priority"] as? String) {
            task.priority = priority
        }
        if let type = self.parseType(args["type"] as? String) {
            task.type = type
        }
        if let status = self.parseStatus(args["status"] as? String) {
            task.applyStatus(status)
        }
        task.updatedAt = .now
        try? self.modelContext.save()
        return self.success(["updated_task_id": task.id, "title": task.title])
    }

    private func markDone(_ args: [String: Any]) -> String {
        guard let task = self.findTask(args) else { return self.error("no matching task") }
        task.applyStatus(.done)
        try? self.modelContext.save()
        return self.success(["marked_done": task.title])
    }

    private func deleteTask(_ args: [String: Any]) -> String {
        if (args["all"] as? Bool) == true {
            return self.bulkDelete(
                completedOnly: (args["completed_only"] as? Bool) == true,
                projectName: args["project_name"] as? String)
        }
        guard let task = self.findTask(args) else { return self.error("no matching task. Pass task_id, match_title, or set all=true.") }
        let title = task.title
        self.modelContext.delete(task)
        try? self.modelContext.save()
        return self.success(["deleted": title])
    }

    private func bulkDelete(completedOnly: Bool, projectName: String?) -> String {
        let allTasks = self.fetchTasks()
        let projects = self.fetchProjects()
        let project = self.matchProject(named: projectName, in: projects)
        let victims = allTasks.filter { task in
            if completedOnly, task.status != .done { return false }
            if let project, task.project?.id != project.id { return false }
            return true
        }
        guard !victims.isEmpty else {
            return self.success(["deleted_count": 0, "note": "nothing matched the criteria"])
        }
        let titles = victims.prefix(10).map(\.title)
        for task in victims {
            self.modelContext.delete(task)
        }
        try? self.modelContext.save()
        return self.success([
            "deleted_count": victims.count,
            "sample_titles": titles,
        ])
    }

    private func handoffToAgent(_ args: [String: Any]) -> String {
        guard let task = self.findTask(args) else { return self.error("no matching task") }
        guard let targetRaw = args["target"] as? String, let target = AgentTarget(rawValue: targetRaw) else {
            return self.error("invalid target")
        }
        let action = task.beginAgentHandoff(to: target)
        Clipboard.copy(action.clipboardText)
        AgentLauncher.open(target, repoPath: action.repoPath)
        try? self.modelContext.save()
        return self.success(["handed_off": task.title, "to": target.label])
    }

    private func openApp(_ args: [String: Any]) -> String {
        guard let appName = (args["app_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty else {
            return self.error("app_name is required")
        }
        if self.blockedApps.contains(where: { $0.compare(appName, options: .caseInsensitive) == .orderedSame }) {
            return self.error("app '\(appName)' is on the safety blocklist")
        }
        let workspace = NSWorkspace.shared
        let url = self.resolveAppURL(named: appName, workspace: workspace)
        guard let url else { return self.error("could not find app named '\(appName)'") }
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return self.success(["opened": url.lastPathComponent])
    }

    private func listToday() -> String {
        let tasks = TaskQueries.todayTasks(from: self.fetchTasks()).prefix(15)
        let items = tasks.map { task in
            [
                "id": task.id,
                "title": task.title,
                "project": task.project?.name ?? "Inbox",
                "priority": task.priority.rawValue,
                "status": task.status.rawValue,
            ]
        }
        return self.success(["today": items])
    }

    private func listInbox() -> String {
        let tasks = TaskQueries.inboxTasks(from: self.fetchTasks()).prefix(15)
        let items = tasks.map { task in
            [
                "id": task.id,
                "title": task.title,
                "priority": task.priority.rawValue,
            ]
        }
        return self.success(["inbox": items])
    }

    private func listProjects() -> String {
        let projects = self.fetchProjects()
        let tasks = self.fetchTasks()
        let items = projects.map { project -> [String: Any] in
            let open = tasks.filter { $0.project?.id == project.id && $0.status != .done }.count
            return ["name": project.name, "open_count": open]
        }
        return self.success(["projects": items])
    }

    private func findTask(_ args: [String: Any]) -> ShipTask? {
        // Title matching is intentionally fuzzy for voice input; spoken titles
        // rarely match exact task strings.
        let tasks = self.fetchTasks()
        if let id = args["task_id"] as? String, let task = tasks.first(where: { $0.id == id }) {
            return task
        }
        if let match = args["match_title"] as? String {
            let lower = match.lowercased()
            return tasks.first { $0.title.lowercased().contains(lower) }
        }
        return nil
    }

    private func fetchTasks() -> [ShipTask] {
        var descriptor = FetchDescriptor<ShipTask>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return (try? self.modelContext.fetch(descriptor)) ?? []
    }

    private func fetchProjects() -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        descriptor.sortBy = [SortDescriptor(\.sortOrder)]
        return (try? self.modelContext.fetch(descriptor)) ?? []
    }

    private func matchProject(named raw: String?, in projects: [Project]) -> Project? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let needle = Self.normalize(raw)
        if needle.isEmpty { return nil }

        // 1. Exact (normalized).
        if let exact = projects.first(where: { Self.normalize($0.name) == needle }) {
            return exact
        }
        // 2. Prefix.
        if let prefix = projects.first(where: { Self.normalize($0.name).hasPrefix(needle) }) {
            return prefix
        }
        // 3. Contains either direction (handles "the LEARN project" → LEARN-X).
        if let contains = projects.first(where: {
            let normalized = Self.normalize($0.name)
            return normalized.contains(needle) || needle.contains(normalized)
        }) {
            return contains
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func parsePriority(_ raw: String?) -> TaskPriority? {
        guard let raw else { return nil }
        return TaskPriority(rawValue: raw.lowercased())
    }

    private func parseType(_ raw: String?) -> TaskType? {
        guard let raw else { return nil }
        return TaskType(rawValue: raw.lowercased())
    }

    private func parseStatus(_ raw: String?) -> TaskStatus? {
        guard let raw else { return nil }
        return TaskStatus(rawValue: raw.lowercased())
    }

    private func resolveAppURL(named name: String, workspace: NSWorkspace) -> URL? {
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            return url
        }
        let direct = URL(fileURLWithPath: "/Applications/\(name).app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let userApps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/\(name).app")
        if FileManager.default.fileExists(atPath: userApps.path) {
            return userApps
        }
        let appURLs = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        return appURLs.first {
            $0.pathExtension == "app" && $0.deletingPathExtension().lastPathComponent.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    private func success(_ payload: [String: Any]) -> String {
        Self.jsonString(["ok": true].merging(payload) { _, new in new })
    }

    private func error(_ message: String) -> String {
        Self.jsonString(["ok": false, "error": message])
    }

    private static func jsonString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return "{\"ok\":false,\"error\":\"serialization\"}" }
        return string
    }
}
