import SwiftData
import SwiftUI

struct TaskDetailView: View {
    @Bindable var task: ShipTask
    @Query(sort: \AgentRun.updatedAt, order: .reverse) private var agentRuns: [AgentRun]
    let projects: [Project]
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirm = false
    @State private var showSource = false
    @State private var showDatePicker = false
    @State private var pickedDate: Date = .now

    init(task: ShipTask, projects: [Project], onDelete: (() -> Void)? = nil) {
        self.task = task
        self.projects = projects
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                self.chipRow
                self.titleField
                self.descriptionField
                self.promptBlock
                if self.hasSource {
                    self.sourceBlock
                }
                if self.hasHistory {
                    self.historyBlock
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 640)
        #endif
        .confirmationDialog(
            "Delete this task?",
            isPresented: self.$showDeleteConfirm,
            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive, action: self.deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: self.task.title) { _, _ in self.save() }
        .onChange(of: self.task.taskDescription) { _, _ in self.save() }
        .onChange(of: self.task.prompt) { _, _ in self.save() }
    }

    @ViewBuilder
    private var chipRow: some View {
        #if os(iOS)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 98), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8)
        {
            self.statusChip
            self.priorityChip
            self.projectChip
            self.dueChip
            self.typeChip
            self.deleteButton
        }
        #else
        HStack(spacing: 8) {
            self.statusChip
            self.priorityChip
            self.projectChip
            self.dueChip
            self.typeChip
            Spacer()
            self.deleteButton
        }
        #endif
    }

    private var deleteButton: some View {
        Button {
            self.showDeleteConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(ShipBarStyle.subtleFill)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(ShipBarStyle.subtleStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("Delete task")
    }

    private var statusChip: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    self.task.applyStatus(status)
                    self.save()
                } label: {
                    if status == self.task.status {
                        Label(status.label, systemImage: "checkmark")
                    } else {
                        Text(status.label)
                    }
                }
            }
        } label: {
            self.chipLabel(
                text: self.task.status.label,
                systemImage: self.task.status == .done ? "checkmark.circle.fill" : "circle",
                tint: self.task.status == .done ? ShipBarStyle.promptGreen : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var priorityChip: some View {
        Menu {
            ForEach(TaskPriority.allCases) { priority in
                Button {
                    self.task.priority = priority
                    self.task.updatedAt = .now
                    self.save()
                } label: {
                    if priority == self.task.priority {
                        Label(priority.label, systemImage: "checkmark")
                    } else {
                        Text(priority.label)
                    }
                }
            }
        } label: {
            self.chipLabel(
                text: self.task.priority.label,
                systemImage: "flag.fill",
                tint: ShipBarStyle.priorityColor(self.task.priority))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var projectChip: some View {
        Menu {
            Button {
                self.task.project = nil
                self.task.isInbox = true
                self.save()
            } label: {
                if self.task.project == nil {
                    Label("Inbox", systemImage: "checkmark")
                } else {
                    Text("Inbox")
                }
            }
            Divider()
            ForEach(self.projects) { project in
                Button {
                    self.task.project = project
                    self.task.isInbox = false
                    self.save()
                } label: {
                    if self.task.project?.id == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            self.chipLabel(
                text: self.task.project?.name ?? "Inbox",
                systemImage: self.task.project == nil ? "tray" : "folder.fill",
                tint: self.task.project == nil ? .orange : ShipBarStyle.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var typeChip: some View {
        Menu {
            ForEach(TaskType.allCases) { type in
                Button {
                    self.task.type = type
                    self.task.updatedAt = .now
                    self.save()
                } label: {
                    if type == self.task.type {
                        Label(type.label, systemImage: "checkmark")
                    } else {
                        Text(type.label)
                    }
                }
            }
        } label: {
            self.chipLabel(
                text: self.task.type.label,
                systemImage: "tag.fill",
                tint: .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var dueChip: some View {
        Menu {
            Button("Today") {
                self.setDueDate(Self.endOfDay(.now))
            }
            Button("Tomorrow") {
                self.setDueDate(Self.endOfDay(Date(timeIntervalSinceNow: 24 * 3_600)))
            }
            Button("This Weekend") {
                self.setDueDate(Self.endOfDay(Self.nextWeekend(from: .now)))
            }
            Button("Pick a date…") {
                self.pickedDate = self.task.dueDate ?? .now
                self.showDatePicker = true
            }
            if self.task.dueDate != nil {
                Divider()
                Button("Clear", role: .destructive) {
                    self.setDueDate(nil)
                }
            }
        } label: {
            self.chipLabel(
                text: self.dueLabelText,
                systemImage: self.dueIconName,
                tint: self.dueTint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: self.$showDatePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker(
                    "Due date",
                    selection: self.$pickedDate,
                    displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Spacer()
                    Button("Cancel") { self.showDatePicker = false }
                    Button("Set") {
                        self.setDueDate(Self.endOfDay(self.pickedDate))
                        self.showDatePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    private var dueLabelText: String {
        guard let due = self.task.dueDate else { return "Anytime" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 0 { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 7 { return due.formatted(.dateTime.weekday(.wide)) }
        return due.formatted(date: .abbreviated, time: .omitted)
    }

    private var dueIconName: String {
        self.task.dueDate == nil ? "calendar.badge.plus" : "calendar"
    }

    private var dueTint: Color {
        guard let due = self.task.dueDate else { return .secondary }
        let today = Calendar.current.startOfDay(for: .now)
        let dueDay = Calendar.current.startOfDay(for: due)
        if dueDay < today { return .red }
        if dueDay == today { return .orange }
        return ShipBarStyle.accent
    }

    private func setDueDate(_ date: Date?) {
        self.task.dueDate = date
        self.task.updatedAt = .now
        self.save()
    }

    private static func endOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date).addingTimeInterval(24 * 3_600 - 1)
    }

    private static func nextWeekend(from date: Date) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Saturday = 7. Days until Saturday; if already weekend, return today.
        if weekday == 7 || weekday == 1 { return date }
        let daysUntilSaturday = (7 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: date) ?? date
    }

    private func chipLabel(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(ShipBarStyle.subtleFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(ShipBarStyle.subtleStroke, lineWidth: 1)
        }
    }

    private var titleField: some View {
        TextField("Untitled task", text: self.$task.title, axis: .vertical)
            .font(.system(size: 22, weight: .semibold))
            .textFieldStyle(.plain)
            .lineLimit(1...3)
    }

    private var descriptionField: some View {
        TextField("Add a description…", text: self.$task.taskDescription, axis: .vertical)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .padding(.bottom, 4)
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Prompt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                if self.task.hasPrompt {
                    Text("\(self.task.prompt.count) chars")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            self.promptEditor

            self.promptActionButtons
        }
    }

    @ViewBuilder
    private var promptActionButtons: some View {
        #if os(iOS)
        VStack(spacing: 8) {
            ForEach(AgentTarget.allCases) { target in
                Button {
                    self.prepareForMac(target)
                } label: {
                    Label("Prepare \(target.label) for Mac", systemImage: target.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minHeight: 44)
                .disabled(!self.task.hasPrompt)
            }
            Text("Saves a truthful Ready on Mac run and copies its prompt. No desktop app is launched from iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        HStack(spacing: 6) {
            ForEach(AgentTarget.allCases) { target in
                Button {
                    let action = AgentWorkflowAction.make(for: target, task: self.task)
                    Clipboard.copy(action.clipboardText)
                } label: {
                    Label("Copy for \(target.label)", systemImage: target.systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!self.task.hasPrompt)
            }
            Spacer()
        }
        #endif
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            if self.task.prompt.isEmpty {
                Text("Tell the agent what to do. This text gets composed with the project's base prompt when you hand off.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(11)
                    .allowsHitTesting(false)
            }
            TextEditor(text: self.$task.prompt)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 140)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShipBarStyle.subtleFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ShipBarStyle.subtleStroke, lineWidth: 1)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                self.showSource.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: self.showSource ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("Source")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    if !self.task.sourceApp.isEmpty {
                        Text(self.task.sourceApp)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if self.showSource {
                VStack(alignment: .leading, spacing: 8) {
                    if !self.task.sourceURL.isEmpty {
                        Text(self.task.sourceURL)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .foregroundStyle(ShipBarStyle.accent)
                    }
                    if !self.task.rawCaptureText.isEmpty {
                        Text(self.task.rawCaptureText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(ShipBarStyle.subtleFill)
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyBlock: some View {
        if let run = AgentRunQueries.latest(for: self.task.id, from: self.agentRuns) {
            HStack(spacing: 6) {
                Image(systemName: run.target?.systemImage ?? "paperplane")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ShipBarStyle.runPurple)
                Text(run.target?.label ?? "Agent run")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                ShipBarStateBadge(runStatus: run.status)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(run.updatedAt.formatted(.relative(presentation: .named)))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.system(size: 11))
        } else if let target = self.task.lastAgentTarget, let at = self.task.lastAgentHandoffAt {
            Label("Sent to \(target.label) · \(at.formatted(.relative(presentation: .named)))", systemImage: target.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var hasSource: Bool {
        !self.task.sourceApp.isEmpty || !self.task.sourceURL.isEmpty || !self.task.rawCaptureText.isEmpty
    }

    private var hasHistory: Bool {
        AgentRunQueries.latest(for: self.task.id, from: self.agentRuns) != nil ||
            (self.task.lastAgentTarget != nil && self.task.lastAgentHandoffAt != nil)
    }

    private func save() {
        ShipBarPersistence.save(self.modelContext, operation: "Save task detail")
    }

    #if os(iOS)
    private func prepareForMac(_ target: AgentTarget) {
        guard AgentLaunchPolicy.behavior(for: target, platform: .iOS) == .prepareForMac else { return }
        let run = AgentRunLifecycle.prepare(task: self.task, target: target, in: self.modelContext)
        let action = AgentWorkflowAction.make(for: target, task: self.task)
        Clipboard.copy(action.clipboardText)
        run.status = .prepared
        ShipBarPersistence.save(self.modelContext, operation: "Prepare agent run for Mac")
    }
    #endif

    private func deleteTask() {
        if let onDelete {
            onDelete()
        } else {
            ShipBarTaskLifecycle.delete(self.task, in: self.modelContext)
            ShipBarPersistence.save(self.modelContext, operation: "Delete task detail")
            self.dismiss()
        }
    }

    private static var horizontalPadding: CGFloat {
        #if os(iOS)
        16
        #else
        22
        #endif
    }
}
