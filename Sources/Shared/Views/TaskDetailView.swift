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
                    Text("Inbox").tag(String?.none)
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

                Toggle("Inbox", isOn: self.$task.isInbox)

                Section("Description") {
                    TextEditor(text: self.$task.taskDescription)
                        .frame(minHeight: 80)
                }

                if !self.task.sourceApp.isEmpty || !self.task.sourceURL.isEmpty || !self.task.rawCaptureText.isEmpty {
                    Section("Source") {
                        if !self.task.sourceApp.isEmpty {
                            TextField("Source app", text: self.$task.sourceApp)
                        }
                        if !self.task.sourceURL.isEmpty {
                            TextField("Source URL", text: self.$task.sourceURL)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                        if !self.task.rawCaptureText.isEmpty {
                            Text(self.task.rawCaptureText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Prompt") {
                    TextEditor(text: self.$task.prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 130)

                    Button("Copy Agent Prompt", systemImage: "doc.on.doc") {
                        Clipboard.copy(PromptComposer.agentPrompt(for: self.task))
                    }
                }

                Section("Agent Actions") {
                    ForEach(AgentTarget.allCases) { target in
                        let action = AgentWorkflowAction.make(for: target, task: self.task)
                        Button("Copy for \(target.label)", systemImage: target.systemImage) {
                            Clipboard.copy(action.clipboardText)
                        }

                        Text(action.launchHint)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                }

                if self.task.hasPrompt {
                    Section("Agent Preview") {
                        Text(PromptComposer.agentPrompt(for: self.task))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Agent Preview") {
                        Text("Add a prompt to make this task agent-ready.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
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
                self.task.isInbox = id == nil
            })
    }
}
