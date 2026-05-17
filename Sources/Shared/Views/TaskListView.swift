import SwiftUI

struct TaskListView: View {
    let title: String
    let tasks: [ShipTask]
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    @State private var statusFilter: TaskStatus?
    @State private var priorityFilter: TaskPriority?
    @State private var typeFilter: TaskType?
    @State private var promptReadyOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer()
                    Text("\(self.filteredTasks.count) open")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Text("Updated just now")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(ShipBarStyle.separator)
                .frame(height: 1)

            self.filterBar

            if self.filteredTasks.isEmpty {
                VStack(spacing: 10) {
                    Text(self.hasActiveFilters ? "No matching tasks" : "No open tasks")
                        .font(.system(size: 17, weight: .semibold))
                    Text(self.hasActiveFilters ? "Clear a filter or capture a new match." : "Capture the next thing worth shipping.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ShipBarProgressBar(progress: self.queuePressure, tint: self.queueTint)
                    HStack(alignment: .firstTextBaseline) {
                        Text(self.queueSummary)
                        Spacer()
                        if self.promptReadyCount > 0 {
                            Label("\(self.promptReadyCount) prompt-ready", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(ShipBarStyle.promptGreen)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(self.filteredTasks) { task in
                            TaskRowView(task: task, selectTask: self.selectTask, toggleDone: self.toggleDone)
                        }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                self.filterMenu(
                    title: self.statusFilter?.label ?? "Status",
                    systemImage: "circle.dashed",
                    isActive: self.statusFilter != nil)
                {
                    Button("Any") { self.statusFilter = nil }
                    Divider()
                    ForEach(TaskStatus.allCases) { status in
                        Button(status.label) { self.statusFilter = status }
                    }
                }

                self.filterMenu(
                    title: self.priorityFilter?.label ?? "Priority",
                    systemImage: "flag",
                    isActive: self.priorityFilter != nil)
                {
                    Button("Any") { self.priorityFilter = nil }
                    Divider()
                    ForEach(TaskPriority.allCases) { priority in
                        Button(priority.label) { self.priorityFilter = priority }
                    }
                }

                self.filterMenu(
                    title: self.typeFilter?.label ?? "Type",
                    systemImage: "tag",
                    isActive: self.typeFilter != nil)
                {
                    Button("Any") { self.typeFilter = nil }
                    Divider()
                    ForEach(TaskType.allCases) { type in
                        Button(type.label) { self.typeFilter = type }
                    }
                }

                Button {
                    self.promptReadyOnly.toggle()
                } label: {
                    Label("Prompt", systemImage: "doc.on.doc")
                }
                .buttonStyle(ShipBarFilterButtonStyle(isActive: self.promptReadyOnly))

                if self.hasActiveFilters {
                    Button("Clear") {
                        self.clearFilters()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func filterMenu<Content: View>(
        title: String,
        systemImage: String,
        isActive: Bool,
        @ViewBuilder content: @escaping () -> Content) -> some View
    {
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(ShipBarFilterButtonStyle(isActive: isActive))
    }

    private var filteredTasks: [ShipTask] {
        self.tasks.filter { task in
            if let statusFilter, task.status != statusFilter {
                return false
            }
            if let priorityFilter, task.priority != priorityFilter {
                return false
            }
            if let typeFilter, task.type != typeFilter {
                return false
            }
            if self.promptReadyOnly, !task.hasPrompt {
                return false
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        self.statusFilter != nil || self.priorityFilter != nil || self.typeFilter != nil || self.promptReadyOnly
    }

    private func clearFilters() {
        self.statusFilter = nil
        self.priorityFilter = nil
        self.typeFilter = nil
        self.promptReadyOnly = false
    }

    private var highPriorityCount: Int {
        self.filteredTasks.filter { $0.priority == .high }.count
    }

    private var promptReadyCount: Int {
        self.filteredTasks.filter(\.hasPrompt).count
    }

    private var queuePressure: Double {
        min(Double(self.filteredTasks.count) / 8, 1)
    }

    private var queueTint: Color {
        self.highPriorityCount > 0 ? ShipBarStyle.priorityColor(.high) : ShipBarStyle.accent
    }

    private var queueSummary: String {
        if self.highPriorityCount > 0 {
            return "\(self.highPriorityCount) high priority"
        }
        return self.filteredTasks.count == 1 ? "1 item in queue" : "\(self.filteredTasks.count) items in queue"
    }
}

private struct ShipBarFilterButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(self.isActive ? Color.white : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous)
                    .fill(self.isActive ? ShipBarStyle.accent : ShipBarStyle.subtleFill)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
