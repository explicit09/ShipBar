import SwiftData
import SwiftUI

struct ProjectWorkspaceView: View {
    @Bindable var project: Project
    let tasks: [ShipTask]
    let runs: [AgentRun]
    let createTask: (CaptureDraft) -> Void
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let handoffToAgent: (ShipTask, AgentTarget) -> Void
    let backToProjects: () -> Void
    let deleteProject: (Project, ShipBarProjectTaskHandling) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteProjectConfirm = false

    init(
        project: Project,
        tasks: [ShipTask],
        runs: [AgentRun] = [],
        createTask: @escaping (CaptureDraft) -> Void,
        selectTask: @escaping (ShipTask) -> Void,
        toggleDone: @escaping (ShipTask) -> Void,
        handoffToAgent: @escaping (ShipTask, AgentTarget) -> Void,
        backToProjects: @escaping () -> Void = {},
        deleteProject: @escaping (Project, ShipBarProjectTaskHandling) -> Void = { _, _ in })
    {
        self.project = project
        self.tasks = tasks
        self.runs = runs
        self.createTask = createTask
        self.selectTask = selectTask
        self.toggleDone = toggleDone
        self.handoffToAgent = handoffToAgent
        self.backToProjects = backToProjects
        self.deleteProject = deleteProject
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                self.header
                Divider()
                self.outcomeSection
                self.healthSection
                Divider()
                self.basePromptSection
                Divider()
                self.quickCaptureSection
                Divider()
                self.statusSection("Todo", status: .todo)
                self.statusSection("Doing", status: .doing)
                self.statusSection("Done", status: .done)
                if !self.recentRuns.isEmpty {
                    Divider()
                    self.recentRunsSection
                }
            }
        }
        .confirmationDialog(
            "Delete \(self.project.name)?",
            isPresented: self.$showDeleteProjectConfirm,
            titleVisibility: .visible)
        {
            Button("Move Tasks to Inbox", role: .destructive) {
                self.deleteProject(self.project, .moveToInbox)
            }
            Button("Delete Project and Tasks", role: .destructive) {
                self.deleteProject(self.project, .deleteTasks)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Moving tasks keeps them in Inbox without this project.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Back to Projects", systemImage: "chevron.left", action: self.backToProjects)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShipBarStyle.accent)
                .help("Return to the project list")

            HStack(alignment: .firstTextBaseline) {
                TextField("Project", text: self.$project.name)
                    .font(.system(size: 22, weight: .bold))
                    .textFieldStyle(.plain)
                    .onSubmit(self.save)
                Spacer()
                Text("\(self.openTasks.count) open")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Move Tasks to Inbox", systemImage: "tray.and.arrow.down") {
                        self.showDeleteProjectConfirm = true
                    }
                    Button("Delete Project and Tasks", systemImage: "trash", role: .destructive) {
                        self.showDeleteProjectConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project actions")
            }

            ShipBarProgressBar(progress: self.doneProgress, tint: ShipBarStyle.promptGreen)
                .frame(height: 5)
        }
    }

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outcome")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField("What will be true when this project ships?", text: self.$project.outcome, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(10)
                .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius))
                .onSubmit(self.save)
                .onChange(of: self.project.outcome) { _, _ in self.save() }
        }
    }

    private var healthSection: some View {
        let health = ProjectQueries.health(project: self.project, tasks: self.tasks, runs: self.runs)
        return HStack(spacing: 8) {
            self.healthMetric("Open", value: health.openCount, tint: ShipBarStyle.shipBlue)
            self.healthMetric("Focus", value: health.focusCount, tint: ShipBarStyle.reviewAmber)
            self.healthMetric("Running", value: health.activeRunCount, tint: ShipBarStyle.runPurple)
            self.healthMetric("Done", value: health.completedCount, tint: ShipBarStyle.successGreen)
        }
    }

    private func healthMetric(_ label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius))
    }

    private var basePromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project Prompt")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(self.project.basePrompt)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ShipBarStyle.accent)
                .disabled(self.project.basePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("Repo path, e.g. /Users/max/Projects/vedit", text: self.$project.repoPath)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .shipBarGlass(radius: ShipBarStyle.controlRadius)
                .onSubmit(self.save)
                .onChange(of: self.project.repoPath) { _, _ in
                    self.save()
                }

            TextEditor(text: self.$project.basePrompt)
                .font(.system(size: 12))
                .frame(minHeight: 72)
                .padding(8)
                .shipBarGlass(radius: ShipBarStyle.controlRadius)
                .onChange(of: self.project.basePrompt) { _, _ in
                    self.save()
                }
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Capture")
                .font(.system(size: 15, weight: .semibold))
            QuickCaptureView(
                projects: [self.project],
                selectedProjectID: self.project.id,
                createTask: self.createTask)
        }
    }

    private func statusSection(_ title: String, status: TaskStatus) -> some View {
        let sectionTasks = self.tasks.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(sectionTasks.count))")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            if sectionTasks.isEmpty {
                Text("No \(title.lowercased()) tasks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sectionTasks) { task in
                        TaskRowView(
                            task: task,
                            selectTask: self.selectTask,
                            toggleDone: self.toggleDone,
                            handoffToAgent: self.handoffToAgent,
                            projects: [self.project],
                            triageToProject: self.triageTask,
                            updateStatus: self.updateStatus,
                            updatePriority: self.updatePriority,
                            updateType: self.updateType)
                    }
                }
            }
        }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent Runs")
                .font(.system(size: 15, weight: .semibold))
            ForEach(self.recentRuns.prefix(3)) { run in
                HStack(spacing: 8) {
                    Circle()
                        .fill(self.runTint(run.status))
                        .frame(width: 7, height: 7)
                    Text(run.taskTitleSnapshot)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(run.statusRawValue.replacingOccurrences(of: "handedOff", with: "handed off").capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentRuns: [AgentRun] {
        self.runs.filter { $0.projectID == self.project.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func runTint(_ status: AgentRunStatus) -> Color {
        switch status {
        case .needsReview: ShipBarStyle.reviewAmber
        case .failed, .canceled: .red
        case .completed: ShipBarStyle.successGreen
        default: ShipBarStyle.runPurple
        }
    }

    private var openTasks: [ShipTask] {
        self.tasks.filter { $0.status != .done }
    }

    private var doneProgress: Double {
        guard !self.tasks.isEmpty else { return 0 }
        return Double(self.tasks.filter { $0.status == .done }.count) / Double(self.tasks.count)
    }

    private func save() {
        self.project.updatedAt = .now
        ShipBarPersistence.save(self.modelContext, operation: "Save project")
    }

    private func triageTask(_ task: ShipTask, to project: Project) {
        task.triage(project: project)
        self.save()
    }

    private func updateStatus(_ task: ShipTask, status: TaskStatus) {
        task.applyStatus(status)
        self.save()
    }

    private func updatePriority(_ task: ShipTask, priority: TaskPriority) {
        task.priority = priority
        task.updatedAt = .now
        self.save()
    }

    private func updateType(_ task: ShipTask, type: TaskType) {
        task.type = type
        task.updatedAt = .now
        self.save()
    }
}
