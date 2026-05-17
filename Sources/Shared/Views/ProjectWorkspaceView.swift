import SwiftData
import SwiftUI

struct ProjectWorkspaceView: View {
    @Bindable var project: Project
    let tasks: [ShipTask]
    let createTask: (CaptureDraft) -> Void
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let handoffToAgent: (ShipTask, AgentTarget) -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                self.header
                Divider()
                self.basePromptSection
                Divider()
                self.quickCaptureSection
                Divider()
                self.statusSection("Todo", status: .todo)
                self.statusSection("Doing", status: .doing)
                self.statusSection("Done", status: .done)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Project", text: self.$project.name)
                    .font(.system(size: 22, weight: .bold))
                    .textFieldStyle(.plain)
                    .onSubmit(self.save)
                Spacer()
                Text("\(self.openTasks.count) open")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ShipBarProgressBar(progress: self.doneProgress, tint: ShipBarStyle.promptGreen)
                .frame(height: 5)
        }
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

    private var openTasks: [ShipTask] {
        self.tasks.filter { $0.status != .done }
    }

    private var doneProgress: Double {
        guard !self.tasks.isEmpty else { return 0 }
        return Double(self.tasks.filter { $0.status == .done }.count) / Double(self.tasks.count)
    }

    private func save() {
        self.project.updatedAt = .now
        try? self.modelContext.save()
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
