#if os(iOS)
import SwiftUI

struct IOSTaskListPane: View {
    enum Mode {
        case today
        case inbox
        case project(String)
        case prompts
    }

    let mode: Mode
    let tasks: [ShipTask]
    let projects: [Project]
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let delete: (ShipTask) -> Void
    let scheduleToday: (ShipTask) -> Void
    let assignProject: (ShipTask, Project) -> Void

    init(
        mode: Mode,
        tasks: [ShipTask],
        projects: [Project],
        selectTask: @escaping (ShipTask) -> Void,
        toggleDone: @escaping (ShipTask) -> Void,
        delete: @escaping (ShipTask) -> Void,
        scheduleToday: @escaping (ShipTask) -> Void = { _ in },
        assignProject: @escaping (ShipTask, Project) -> Void = { _, _ in })
    {
        self.mode = mode
        self.tasks = tasks
        self.projects = projects
        self.selectTask = selectTask
        self.toggleDone = toggleDone
        self.delete = delete
        self.scheduleToday = scheduleToday
        self.assignProject = assignProject
    }

    var body: some View {
        if self.tasks.isEmpty {
            self.emptyState
        } else {
            List {
                ForEach(self.groupedSections, id: \.0) { section in
                    let title = section.0
                    let rows = section.1
                    if let title, !title.isEmpty {
                        Section {
                            ForEach(rows) { task in
                                self.row(for: task)
                                    .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                                    .listRowSeparator(.visible)
                            }
                        } header: {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.6)
                                .padding(.top, 6)
                        }
                    } else {
                        Section {
                            ForEach(rows) { task in
                                self.row(for: task)
                                    .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                                    .listRowSeparator(.visible)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for task: ShipTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                self.toggleDone(task)
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.status == .done ? ShipBarStyle.promptGreen : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == .done ? "Mark task open" : "Mark task done")

            Button {
                self.selectTask(task)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(ShipBarStyle.priorityColor(task.priority))
                                .frame(width: 7, height: 7)
                            Text(task.title)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        let meta = self.metaParts(for: task)
                        if !meta.isEmpty {
                            Text(meta.joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let dueText = self.dueText(for: task) {
                        Text(dueText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.dueColor(for: task))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(self.dueColor(for: task).opacity(0.12))
                            }
                    }
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(self.accessibilityLabel(for: task))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                self.toggleDone(task)
            } label: {
                Label(task.status == .done ? "Undo" : "Done", systemImage: "checkmark")
            }
            .tint(ShipBarStyle.promptGreen)
            if case .inbox = self.mode {
                Button {
                    self.scheduleToday(task)
                } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                self.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if case .inbox = self.mode {
                Menu {
                    ForEach(self.projects) { project in
                        Button(project.name) { self.assignProject(task, project) }
                    }
                } label: {
                    Label("Project", systemImage: "folder")
                }
                .tint(ShipBarStyle.accent)
            }
        }
    }

    private func accessibilityLabel(for task: ShipTask) -> String {
        var parts = [task.title]
        parts.append(contentsOf: self.metaParts(for: task))
        if let dueText = self.dueText(for: task) {
            parts.append(dueText)
        }
        return parts.joined(separator: ", ")
    }

    private var groupedSections: [(String?, [ShipTask])] {
        switch self.mode {
        case .inbox:
            return [(nil, self.tasks)]
        case let .project(projectName):
            return [(projectName, self.tasks)]
        case .prompts:
            let grouped = Dictionary(grouping: self.tasks) { task -> String in
                task.project?.name ?? "Inbox"
            }
            return grouped
                .sorted { lhs, rhs in
                    if lhs.key == "Inbox" { return true }
                    if rhs.key == "Inbox" { return false }
                    return lhs.key < rhs.key
                }
                .map { ($0.key, $0.value) }
        case .today:
            let grouped = Dictionary(grouping: self.tasks) { task -> String in
                task.project?.name ?? "Inbox"
            }
            return grouped
                .sorted { lhs, rhs in
                    if lhs.key == "Inbox" { return true }
                    if rhs.key == "Inbox" { return false }
                    return lhs.key < rhs.key
                }
                .map { ($0.key, $0.value) }
        }
    }

    private func metaParts(for task: ShipTask) -> [String] {
        var parts: [String] = []
        // Inline project tag — section headers exist but inline keeps context
        // when you scroll past a header.
        if let name = task.project?.name {
            parts.append(name)
        } else if task.isInbox {
            parts.append("Inbox")
        }
        if task.hasPrompt { parts.append("Prompt") }
        if let target = task.lastAgentTarget {
            parts.append("→ \(target.label)")
        }
        return parts
    }

    private func dueText(for task: ShipTask) -> String? {
        guard let due = task.dueDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 0 { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 7 { return due.formatted(.dateTime.weekday(.short)) }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    private func dueColor(for task: ShipTask) -> Color {
        guard let due = task.dueDate else { return .secondary }
        let today = Calendar.current.startOfDay(for: .now)
        let dueDay = Calendar.current.startOfDay(for: due)
        if dueDay < today { return .red }
        if dueDay == today { return .orange }
        return ShipBarStyle.accent
    }

    private var emptyState: some View {
        let copy = self.emptyCopy
        return VStack(spacing: 6) {
            Image(systemName: self.emptyStateImageName)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(copy.0)
                .font(.system(size: 17, weight: .semibold))
            Text(copy.1)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCopy: (String, String) {
        switch self.mode {
        case .today: return ("Nothing due today", "Capture something or schedule a task.")
        case .inbox: return ("Inbox is clear", "Untriaged captures will land here.")
        case .project: return ("No open tasks", "Capture a task for this project.")
        case .prompts: return ("No prompt-ready tasks", "Add prompts to tasks you want to hand off.")
        }
    }

    private var emptyStateImageName: String {
        switch self.mode {
        case .today: "checkmark.circle"
        case .inbox: "tray"
        case .project: "folder"
        case .prompts: "doc.on.doc"
        }
    }
}
#endif
