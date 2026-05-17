import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ShipBarRootView: View {
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \ShipTask.createdAt, order: .reverse) private var tasks: [ShipTask]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedProjectID: String?
    @State private var selectedTask: ShipTask?
    @State private var selectedSection = ShipBarSection.buildBar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShipBarSectionSwitcherView(selectedSection: self.$selectedSection)

            self.sectionContent
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            HStack {
                Button("New Project", systemImage: "folder.badge.plus", action: self.createProject)
                    .buttonStyle(.plain)
                Spacer()
                #if os(macOS)
                Button("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                #endif
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, ShipBarStyle.contentPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .modifier(ShipBarPanelSurface())
        .sheet(item: self.$selectedTask) { task in
            TaskDetailView(task: task, projects: self.projects)
                .presentationDetents([.medium, .large])
        }
        .task {
            self.seedDefaultProjectIfNeeded()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch self.selectedSection {
        case .buildBar:
            ShipBarDashboardView(
                projects: self.projects,
                tasks: self.tasks,
                selectedProjectID: self.selectedProjectID,
                createProject: self.createProject,
                createTask: self.createTask(from:),
                selectProject: self.selectProject,
                selectTask: { self.selectedTask = $0 },
                toggleDone: self.toggleDone)
        case .projects:
            ShipBarDashboardView(
                projects: self.projects,
                tasks: self.tasks,
                selectedProjectID: self.selectedProjectID,
                createProject: self.createProject,
                createTask: self.createTask(from:),
                selectProject: self.selectProject,
                selectTask: { self.selectedTask = $0 },
                toggleDone: self.toggleDone)
        case .tasks:
            TaskListView(
                title: self.selectedProject?.name ?? "Tasks",
                tasks: self.visibleTasks,
                selectTask: { self.selectedTask = $0 },
                toggleDone: self.toggleDone)
        case .prompts:
            TaskListView(
                title: "Prompts",
                tasks: self.tasks.filter(\.hasPrompt),
                selectTask: { self.selectedTask = $0 },
                toggleDone: self.toggleDone)
        case .agents:
            VStack(alignment: .leading, spacing: 12) {
                Text("Agents")
                    .font(.system(size: 22, weight: .bold))
                Divider()
                Label("Claude Code", systemImage: "sparkles")
                Label("Codex", systemImage: "circle.hexagongrid")
                Label("Cursor", systemImage: "cube.fill")
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
        case .settings:
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                Divider()
                Text("CloudKit sync")
                Text("Prompt templates")
                Text("About ShipBar")
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
        }
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return self.projects.first { $0.id == selectedProjectID }
    }

    private var visibleTasks: [ShipTask] {
        if let selectedProject {
            return TaskQueries.tasks(for: selectedProject, from: self.tasks)
        }
        return TaskQueries.todayTasks(from: self.tasks)
    }

    private func createTask(from draft: CaptureDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let resolvedProject = self.project(for: draft.projectID ?? self.selectedProjectID) ?? self.projects.first
        let task = ShipTask(
            title: title,
            priority: draft.priority,
            type: draft.type,
            project: resolvedProject)
        self.modelContext.insert(task)
        try? self.modelContext.save()
    }

    private func toggleDone(_ task: ShipTask) {
        task.applyStatus(task.status == .done ? .todo : .done)
        try? self.modelContext.save()
    }

    private func createProject() {
        let project = Project(name: "New Project", sortOrder: self.projects.count)
        self.modelContext.insert(project)
        self.selectedProjectID = project.id
        self.selectedSection = .projects
        try? self.modelContext.save()
    }

    private func selectProject(_ project: Project) {
        self.selectedProjectID = project.id
        self.selectedSection = .tasks
    }

    private func project(for id: String?) -> Project? {
        guard let id else { return nil }
        return self.projects.first { $0.id == id }
    }

    private func seedDefaultProjectIfNeeded() {
        guard self.projects.isEmpty else { return }
        let defaults = [
            ("LEARN-X", "purple"),
            ("vedit", "green"),
            ("Technologia", "orange"),
        ]
        for (index, name) in defaults.enumerated() {
            self.modelContext.insert(Project(name: name.0, color: name.1, sortOrder: index))
        }
        try? self.modelContext.save()
    }
}
