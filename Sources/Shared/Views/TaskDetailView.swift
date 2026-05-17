import SwiftData
import SwiftUI

struct TaskDetailView: View {
    @Bindable var task: ShipTask
    let projects: [Project]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                TextField("Short task", text: self.$task.title)

                Picker("Project", selection: self.projectSelection) {
                    Text("No Project").tag(String?.none)
                    ForEach(self.projects) { project in
                        Text(project.name).tag(String?.some(project.id))
                    }
                }

                Picker("Status", selection: self.statusSelection) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }

                Picker("Priority", selection: self.$task.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }

                Picker("Type", selection: self.$task.type) {
                    ForEach(TaskType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                Section("Description") {
                    TextEditor(text: self.$task.taskDescription)
                        .frame(minHeight: 80)
                }

                Section("Prompt") {
                    TextEditor(text: self.$task.prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 130)

                    Button("Copy Prompt", systemImage: "doc.on.doc") {
                        Clipboard.copy(self.task.prompt)
                    }
                    .disabled(!self.task.hasPrompt)
                }
            }
            .navigationTitle("Task")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? self.modelContext.save()
                        self.dismiss()
                    }
                }
            }
        }
    }

    private var statusSelection: Binding<TaskStatus> {
        Binding(
            get: { self.task.status },
            set: { self.task.applyStatus($0) })
    }

    private var projectSelection: Binding<String?> {
        Binding(
            get: { self.task.project?.id },
            set: { id in
                self.task.project = self.projects.first { $0.id == id }
            })
    }
}
