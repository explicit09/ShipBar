#if os(iOS)
import SwiftUI

struct IOSTodayPane: View {
    let tasks: [ShipTask]
    let runs: [AgentRun]
    let inboxCount: Int
    let projects: [Project]
    let openCount: (Project) -> Int
    let onCreateCapture: () -> Void
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let setFocus: (ShipTask) -> Void
    let removeFocus: (ShipTask) -> Void
    let delete: (ShipTask) -> Void
    let openInbox: () -> Void
    let openProject: (Project) -> Void
    let newProject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                self.titleRow
                self.statsRow
                self.flightPlanCard
                self.todayCard
                self.waitingCard
                self.inboxRow
                self.projectsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.system(size: 34, weight: .bold))
            Spacer()
            Button(action: self.onCreateCapture) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ShipBarStyle.accent)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(Color(.tertiarySystemFill))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick Capture")
        }
    }

    private var statsRow: some View {
        HStack {
            Text("\(self.focusedTasks.count)/3 focused · \(self.groups.completed.count) done")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: self.openInbox) {
                HStack(spacing: 6) {
                    Text(self.inboxCount == 1 ? "1 inbox" : "\(self.inboxCount) inbox")
                        .foregroundStyle(.secondary)
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(self.inboxCount > 0 ? ShipBarStyle.reviewAmber : .secondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var todayCard: some View {
        if self.actionableTasks.isEmpty {
            IOSCard {
                IOSCardSectionHeader(title: "Today")
                VStack(spacing: 4) {
                    Text("Nothing due today")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Capture something or schedule a task.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        } else {
            IOSCard {
                IOSCardSectionHeader(title: "Today")
                VStack(spacing: 0) {
                    ForEach(Array(self.actionableTasks.enumerated()), id: \.element.id) { index, task in
                        IOSTaskRow(
                            task: task,
                            selectTask: self.selectTask,
                            toggleDone: self.toggleDone,
                            delete: self.delete)
                        if index < self.actionableTasks.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var flightPlanCard: some View {
        IOSCard {
            IOSCardSectionHeader(title: "Flight Plan")
            VStack(spacing: 0) {
                ForEach(Array(self.focusedTasks.enumerated()), id: \.element.id) { index, task in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(ShipBarStyle.shipBlue)
                            .frame(width: 28, height: 28)
                            .background(ShipBarStyle.shipBlue.opacity(0.14), in: Circle())
                        Button { self.selectTask(task) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(task.project?.name ?? "Inbox").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button { self.removeFocus(task) } label: {
                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(task.title) from today's focus")
                    }
                    .padding(.leading, 14)
                    if index < self.focusedTasks.count - 1 { Divider().padding(.leading, 54) }
                }
                if self.focusedTasks.count < FocusCoordinator.maximumCount {
                    Menu {
                        ForEach(self.focusCandidates) { task in
                            Button(task.title) { self.setFocus(task) }
                        }
                    } label: {
                        Label("Choose focus task", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ShipBarStyle.shipBlue)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    .disabled(self.focusCandidates.isEmpty)
                }
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var waitingCard: some View {
        if !self.groups.waiting.isEmpty {
            IOSCard {
                IOSCardSectionHeader(title: "Waiting")
                ForEach(self.groups.waiting) { task in
                    Button { self.selectTask(task) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass").foregroundStyle(ShipBarStyle.reviewAmber)
                            Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            if let run = AgentRunQueries.latest(for: task.id, from: self.runs) {
                                Text(run.status == .prepared ? "Ready on Mac" : run.statusRawValue.capitalized)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ShipBarStyle.runPurple)
                            }
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groups: TodayTaskGroups {
        TaskQueries.todayGroups(from: self.tasks, runs: self.runs)
    }

    private var actionableTasks: [ShipTask] {
        [self.groups.now].compactMap { $0 } + self.groups.next
    }

    private var focusedTasks: [ShipTask] {
        FocusCoordinator.focusedTasks(in: self.tasks, on: .now)
    }

    private var focusCandidates: [ShipTask] {
        let focusedIDs = Set(self.focusedTasks.map(\.id))
        return self.tasks.filter { $0.status != .done && !focusedIDs.contains($0.id) }.prefix(8).map { $0 }
    }

    private var inboxRow: some View {
        Button(action: self.openInbox) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ShipBarStyle.reviewAmber.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ShipBarStyle.reviewAmber)
                }
                Text("Inbox")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(self.inboxCount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: ShipBarStyle.pageRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
        }
        .buttonStyle(.plain)
    }

    private var projectsCard: some View {
        IOSCard {
            IOSCardSectionHeader(title: "Projects")
            VStack(spacing: 0) {
                ForEach(Array(self.projects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        self.openProject(project)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(self.tint(for: project))
                                .frame(width: 22)
                            Text(project.name)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(self.openCount(project))")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < self.projects.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
                if !self.projects.isEmpty {
                    Divider().padding(.leading, 50)
                }
                Button(action: self.newProject) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15))
                            .foregroundStyle(ShipBarStyle.accent)
                            .frame(width: 22)
                        Text("New Project")
                            .font(.system(size: 15))
                            .foregroundStyle(ShipBarStyle.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
        }
    }

    private func tint(for project: Project) -> Color {
        switch project.color {
        case "green": ShipBarStyle.promptGreen
        case "orange": .orange
        case "purple": .purple
        case "yellow": .yellow
        case "red": .red
        default: ShipBarStyle.accent
        }
    }
}

struct IOSTaskRow: View {
    let task: ShipTask
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    let delete: (ShipTask) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                self.toggleDone(self.task)
            } label: {
                Image(systemName: self.task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(self.task.status == .done ? ShipBarStyle.promptGreen : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.task.status == .done ? "Mark task open" : "Mark task done")

            Button {
                self.selectTask(self.task)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(self.statusDotColor)
                        .frame(width: 8, height: 8)

                    Text(self.task.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(self.task.project?.name ?? "Inbox")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(self.task.title), \(self.task.project?.name ?? "Inbox")")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                self.delete(self.task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusDotColor: Color {
        switch self.task.status {
        case .doing: ShipBarStyle.accent
        case .done: ShipBarStyle.promptGreen
        case .todo: Color(.tertiaryLabel)
        }
    }
}
#endif
