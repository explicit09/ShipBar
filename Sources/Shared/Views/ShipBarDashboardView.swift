import SwiftUI

struct ShipBarDashboardView: View {
    let projects: [Project]
    let tasks: [ShipTask]
    let selectedProjectID: String?
    let createProject: () -> Void
    let createTask: (CaptureDraft) -> Void
    let selectProject: (Project) -> Void
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let handoffToAgent: (ShipTask, AgentTarget) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                self.header
                Divider()
                self.inboxSection
                Divider()
                self.projectsSection
                Divider()
                self.todaySection
                Divider()
                self.quickCaptureSection
                Divider()
                self.aiToolsSection
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("BuildBar")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("Max")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ShipBarStyle.accent)
            }
            Text("Ship better. Every day.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Projects")
                .font(.system(size: 15, weight: .semibold))

            ForEach(self.projects.prefix(5)) { project in
                Button {
                    self.selectProject(project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(self.projectColor(project))
                            .frame(width: 18)
                        Text(project.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(self.openCount(for: project)) open")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button("New Project", systemImage: "plus", action: self.createProject)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ShipBarStyle.accent)
                .padding(.top, 2)
        }
    }

    private var inboxSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.inboxTasks.isEmpty ? Color.secondary : Color.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Inbox")
                    .font(.system(size: 14, weight: .semibold))
                Text("Untriaged captures")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(self.inboxTasks.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.inboxTasks.isEmpty ? Color.secondary : Color.orange)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today (\(self.todayTasks.count))")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("View all") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ShipBarStyle.accent)
            }

            ForEach(self.todayTasks.prefix(5)) { task in
                TaskRowView(
                    task: task,
                    selectTask: self.selectTask,
                    toggleDone: self.toggleDone,
                    handoffToAgent: self.handoffToAgent)
            }

            Button("Add Task", systemImage: "plus") {}
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ShipBarStyle.accent)
                .padding(.top, 1)
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Capture")
                .font(.system(size: 15, weight: .semibold))
            QuickCaptureView(
                projects: self.projects,
                selectedProjectID: self.selectedProjectID,
                createTask: self.createTask)
        }
    }

    private var aiToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Tools")
                .font(.system(size: 15, weight: .semibold))
            HStack {
                self.aiToolLabel("Claude Code", image: "sparkles", tint: .orange)
                Spacer()
                self.aiToolLabel("Codex", image: "circle.hexagongrid", tint: .primary)
                Spacer()
                self.aiToolLabel("Cursor", image: "cube.fill", tint: .secondary)
            }
        }
    }

    private var todayTasks: [ShipTask] {
        TaskQueries.todayTasks(from: self.tasks)
    }

    private var inboxTasks: [ShipTask] {
        TaskQueries.inboxTasks(from: self.tasks)
    }

    private func aiToolLabel(_ title: String, image: String, tint: Color) -> some View {
        Label(title, systemImage: image)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary, tint)
            .symbolRenderingMode(.hierarchical)
    }

    private func openCount(for project: Project) -> Int {
        self.tasks.filter { $0.project?.id == project.id && $0.status != .done }.count
    }

    private func projectColor(_ project: Project) -> Color {
        switch project.color {
        case "green": ShipBarStyle.promptGreen
        case "orange": .orange
        case "purple": .purple
        case "yellow": .yellow
        default: ShipBarStyle.accent
        }
    }
}
