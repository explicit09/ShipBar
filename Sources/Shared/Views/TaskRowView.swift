import SwiftUI

struct TaskRowView: View {
    let task: ShipTask
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let handoffToAgent: (ShipTask, AgentTarget) -> Void
    let projects: [Project]
    let triageToProject: (ShipTask, Project) -> Void
    let updateStatus: (ShipTask, TaskStatus) -> Void
    let updatePriority: (ShipTask, TaskPriority) -> Void
    let updateType: (ShipTask, TaskType) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        task: ShipTask,
        selectTask: @escaping (ShipTask) -> Void,
        toggleDone: @escaping (ShipTask) -> Void,
        handoffToAgent: @escaping (ShipTask, AgentTarget) -> Void,
        projects: [Project] = [],
        triageToProject: @escaping (ShipTask, Project) -> Void = { _, _ in },
        updateStatus: @escaping (ShipTask, TaskStatus) -> Void = { _, _ in },
        updatePriority: @escaping (ShipTask, TaskPriority) -> Void = { _, _ in },
        updateType: @escaping (ShipTask, TaskType) -> Void = { _, _ in })
    {
        self.task = task
        self.selectTask = selectTask
        self.toggleDone = toggleDone
        self.handoffToAgent = handoffToAgent
        self.projects = projects
        self.triageToProject = triageToProject
        self.updateStatus = updateStatus
        self.updatePriority = updatePriority
        self.updateType = updateType
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                self.toggleDone(self.task)
            } label: {
                Image(systemName: self.task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(self.task.status == .done ? ShipBarStyle.promptGreen : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(self.task.status == .done ? "Reopen \(self.task.title)" : "Mark \(self.task.title) done")

            Button {
                self.selectTask(self.task)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(self.task.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(priorityColor)
                                .frame(width: 6, height: 6)
                            Text(self.task.priority.label)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text(self.task.isInbox ? "Inbox" : (self.task.project?.name ?? "No Project"))
                        Text("·")
                        if let lastAgentTarget = self.task.lastAgentTarget {
                            Label(lastAgentTarget.label, systemImage: lastAgentTarget.systemImage)
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(ShipBarStyle.runPurple)
                        } else if self.task.hasPrompt {
                            Label("Ready", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(ShipBarStyle.promptGreen)
                        } else {
                            Text(self.task.type.label)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.taskAccessibilityLabel)

            if !self.projects.isEmpty {
                Menu {
                    Section("Project") {
                        ForEach(self.projects) { project in
                            Button(project.name, systemImage: self.task.project?.id == project.id ? "checkmark" : "folder") {
                                self.triageToProject(self.task, project)
                            }
                        }
                    }

                    Section("Status") {
                        ForEach(TaskStatus.allCases) { status in
                            Button(status.label, systemImage: self.task.status == status ? "checkmark" : "circle") {
                                self.updateStatus(self.task, status)
                            }
                        }
                    }

                    Section("Priority") {
                        ForEach(TaskPriority.allCases) { priority in
                            Button(priority.label, systemImage: self.task.priority == priority ? "checkmark" : "flag") {
                                self.updatePriority(self.task, priority)
                            }
                        }
                    }

                    Section("Type") {
                        ForEach(TaskType.allCases) { type in
                            Button(type.label, systemImage: self.task.type == type ? "checkmark" : "tag") {
                                self.updateType(self.task, type)
                            }
                        }
                    }
                } label: {
                    Image(systemName: self.task.isInbox ? "tray.and.arrow.up" : "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.task.isInbox ? Color.orange : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityLabel("Edit project, status, priority, or type for \(self.task.title)")
            }

            Menu {
                ForEach(AgentTarget.allCases) { target in
                    Button("Copy for \(target.label)", systemImage: target.systemImage) {
                        self.handoffToAgent(self.task, target)
                    }
                }
            } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.task.hasPrompt ? ShipBarStyle.accent : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel("Hand off \(self.task.title) to an agent")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: ShipBarStyle.rowRadius, style: .continuous)
                .fill(ShipBarStyle.raisedSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ShipBarStyle.rowRadius, style: .continuous)
                .stroke(
                    Color.primary.opacity(self.contrast == .increased ? 0.34 : 0.10),
                    lineWidth: self.contrast == .increased ? 2 : 1)
        }
        .padding(.vertical, 3)
    }

    private var priorityColor: Color {
        ShipBarStyle.priorityColor(self.task.priority)
    }

    private var taskAccessibilityLabel: String {
        let location = self.task.isInbox ? "Inbox" : (self.task.project?.name ?? "No project")
        let readiness: String
        if let target = self.task.lastAgentTarget {
            readiness = "Last handed to \(target.label)"
        } else if self.task.hasPrompt {
            readiness = "Prompt ready"
        } else {
            readiness = self.task.type.label
        }
        return "\(self.task.title), \(self.task.status.label), \(self.task.priority.label) priority, \(location), \(readiness)"
    }
}

extension TaskRowView {
    init(
        task: ShipTask,
        selectTask: @escaping (ShipTask) -> Void,
        toggleDone: @escaping (ShipTask) -> Void)
    {
        self.init(
            task: task,
            selectTask: selectTask,
            toggleDone: toggleDone,
            handoffToAgent: { _, _ in })
    }
}
