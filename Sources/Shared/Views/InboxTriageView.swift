import SwiftData
import SwiftUI

struct InboxTriageView: View {
    let tasks: [ShipTask]
    let allTasks: [ShipTask]
    let projects: [Project]
    let createTask: (CaptureDraft) -> Void
    let selectTask: (ShipTask) -> Void
    let deleteTask: (ShipTask) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var selection: Set<String> = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShipBarPageHeader(title: "Inbox", purpose: "Clarify, schedule, or discard captured work.")

            QuickCaptureView(
                projects: self.projects,
                selectedProjectID: nil,
                createTask: self.createTask,
                placeholder: ShipBarDestination.capturePrompt)

            HStack(alignment: .firstTextBaseline) {
                Text(self.selection.isEmpty ? "Select work to triage in batches." : "\(self.selection.count) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !self.tasks.isEmpty {
                    Button(self.selection.count == self.tasks.count ? "Clear" : "Select All") {
                        self.selection = self.selection.count == self.tasks.count ? [] : Set(self.tasks.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShipBarStyle.accent)
                }
            }

            Divider()

            if self.tasks.isEmpty {
                ContentUnavailableView(
                    "Inbox is clear",
                    systemImage: "tray",
                    description: Text("New untriaged captures will land here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(self.tasks) { task in
                            self.taskRow(task)
                        }
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            if !self.selection.isEmpty {
                self.batchBar
                    .padding(.top, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: self.selection)
        .confirmationDialog(
            "Delete \(self.selection.count) selected task\(self.selection.count == 1 ? "" : "s")?",
            isPresented: self.$confirmDelete,
            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive, action: self.deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        #if os(macOS)
        .onExitCommand { self.selection.removeAll() }
        .background {
            Button("") { self.selection.removeAll() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        #endif
    }

    private func taskRow(_ task: ShipTask) -> some View {
        let isSelected = self.selection.contains(task.id)
        return HStack(spacing: 10) {
            Button {
                self.toggleSelection(task.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? ShipBarStyle.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(task.title)" : "Select \(task.title)")

            Button {
                self.selectTask(task)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(task.priority.label)
                        if task.hasPrompt { Label("Ready", systemImage: "doc.on.doc") }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Today", systemImage: "sun.max") { self.schedule([task]) }
                Menu("Assign Project") {
                    ForEach(self.projects) { project in
                        Button(project.name) { self.assign([task], to: project) }
                    }
                }
                Button("Someday", systemImage: "moon.stars") { self.someday([task]) }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    self.selection = [task.id]
                    self.confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Triage \(task.title)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            isSelected ? ShipBarStyle.accent.opacity(0.11) : ShipBarStyle.raisedSurface,
            in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius))
    }

    private var batchBar: some View {
        HStack(spacing: 8) {
            Text("\(self.selection.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(ShipBarStyle.accent.opacity(0.18), in: Circle())

            Menu {
                ForEach(self.projects) { project in
                    Button(project.name) { self.assign(self.selectedTasks, to: project) }
                }
            } label: {
                Label("Project", systemImage: "folder")
            }
            .disabled(self.projects.isEmpty)

            Button { self.schedule(self.selectedTasks) } label: {
                Label("Today", systemImage: "sun.max")
            }
            Button { self.someday(self.selectedTasks) } label: {
                Label("Someday", systemImage: "moon.stars")
            }
            Spacer()
            Button(role: .destructive) { self.confirmDelete = true } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete selected tasks")
        }
        .font(.system(size: 11, weight: .semibold))
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var selectedTasks: [ShipTask] {
        self.tasks.filter { self.selection.contains($0.id) }
    }

    private func toggleSelection(_ id: String) {
        if self.selection.contains(id) { self.selection.remove(id) } else { self.selection.insert(id) }
    }

    private func assign(_ tasks: [ShipTask], to project: Project) {
        InboxBatchCoordinator.assign(tasks, to: project)
        self.finishBatch("Assign Inbox tasks")
    }

    private func schedule(_ tasks: [ShipTask]) {
        InboxBatchCoordinator.scheduleToday(tasks, among: self.allTasks)
        self.finishBatch("Schedule Inbox tasks")
    }

    private func someday(_ tasks: [ShipTask]) {
        InboxBatchCoordinator.moveToSomeday(tasks, among: self.allTasks)
        self.finishBatch("Move Inbox tasks to Someday")
    }

    private func finishBatch(_ operation: String) {
        ShipBarPersistence.save(self.modelContext, operation: operation)
        self.selection.removeAll()
    }

    private func deleteSelected() {
        let doomed = self.selectedTasks
        self.selection.removeAll()
        for task in doomed { self.deleteTask(task) }
    }
}
