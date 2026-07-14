import SwiftUI

struct TodayCommandCenterView: View {
    let tasks: [ShipTask]
    let runs: [AgentRun]
    let setFocus: (ShipTask) -> Void
    let removeFocus: (ShipTask) -> Void
    let moveFocus: (ShipTask, Int) -> Void
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    @State private var showCompleted = false

    private var groups: TodayTaskGroups {
        TaskQueries.todayGroups(from: self.tasks, runs: self.runs)
    }

    private var focusedTasks: [ShipTask] {
        FocusCoordinator.focusedTasks(in: self.tasks, on: .now)
    }

    private var focusCandidates: [ShipTask] {
        let focusedIDs = Set(self.focusedTasks.map(\.id))
        return self.tasks
            .filter { $0.status != .done && !focusedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                self.progressHeader
                self.flightPlan
                self.workflow
            }
            .padding(.bottom, 8)
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(self.headerTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.5)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(ShipBarStyle.progressTrack, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: self.completionProgress)
                    .stroke(ShipBarStyle.successGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(self.completionProgress * 100))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)
            .accessibilityLabel("Today's completion")
            .accessibilityValue("\(Int(self.completionProgress * 100)) percent")
        }
    }

    private var flightPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Flight plan", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(ShipBarStyle.selectionForeground)
                Spacer()
                Text("\(self.focusedTasks.count)/3")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(self.focusedTasks.enumerated()), id: \.element.id) { index, task in
                FocusTaskRowView(
                    task: task,
                    mode: .flightPlan(position: index + 1),
                    selectTask: self.selectTask,
                    toggleDone: self.toggleDone,
                    removeFocus: self.removeFocus,
                    moveFocus: self.moveFocus)
            }

            if self.focusedTasks.count < FocusCoordinator.maximumCount {
                Menu {
                    if self.focusCandidates.isEmpty {
                        Text("No open tasks available")
                    } else {
                        ForEach(self.focusCandidates.prefix(12)) { task in
                            Button(task.title) { self.setFocus(task) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Choose focus task")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("Slot \(self.focusedTasks.count + 1)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(ShipBarStyle.subtleStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: ShipBarStyle.pageRadius, style: .continuous)
                .fill(ShipBarStyle.flightPlanSurface)
        }
        .shipBarOutline(
            radius: ShipBarStyle.pageRadius,
            color: ShipBarStyle.subtleStroke,
            increasedColor: ShipBarStyle.increasedContrastStroke)
    }

    @ViewBuilder
    private var workflow: some View {
        if self.groups.now == nil && self.groups.next.isEmpty && self.groups.waiting.isEmpty {
            self.emptyWorkflow
        } else {
            if let nowTask = self.groups.now {
                self.sectionLabel("Now", detail: "Your current ship target")
                FocusTaskRowView(
                    task: nowTask,
                    mode: .now,
                    selectTask: self.selectTask,
                    toggleDone: self.toggleDone)
            }

            if !self.groups.next.isEmpty {
                self.sectionLabel("Next", detail: "Ready when you are")
                ForEach(self.groups.next) { task in
                    FocusTaskRowView(
                        task: task,
                        mode: .next,
                        backgroundFillOpacity: 0.72,
                        selectTask: self.selectTask,
                        toggleDone: self.toggleDone)
                }
            }

            if !self.groups.waiting.isEmpty {
                self.sectionLabel("Waiting", detail: "Agents and reviews")
                ForEach(self.groups.waiting) { task in
                    FocusTaskRowView(
                        task: task,
                        mode: .waiting(self.latestRun(for: task)?.status ?? .running),
                        backgroundFillOpacity: 0.72,
                        selectTask: self.selectTask,
                        toggleDone: self.toggleDone)
                }
            }
        }

        if !self.groups.completed.isEmpty {
            DisclosureGroup(isExpanded: self.$showCompleted) {
                VStack(spacing: 6) {
                    ForEach(self.groups.completed) { task in
                        FocusTaskRowView(
                            task: task,
                            mode: .next,
                            selectTask: self.selectTask,
                            toggleDone: self.toggleDone)
                            .opacity(0.68)
                    }
                }
                .padding(.top, 7)
            } label: {
                HStack {
                    Label("Completed today", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Text("\(self.groups.completed.count)")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShipBarStyle.successGreen)
            }
            .tint(.secondary)
        }
    }

    private var emptyWorkflow: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ShipBarStyle.selectionForeground)
            Text("Choose what ships today")
                .font(.system(size: 14, weight: .semibold))
            Text("Add up to three tasks to your Flight Plan. The first becomes your current target.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func sectionLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func latestRun(for task: ShipTask) -> AgentRun? {
        self.runs
            .filter { $0.taskID == task.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var headerTitle: String {
        if let nowTask = self.groups.now {
            return "Ship \(nowTask.title)"
        }
        if !self.groups.waiting.isEmpty { return "Review what came back" }
        return "Set today's direction"
    }

    private var completionProgress: Double {
        let completedCount = self.groups.completed.count
        let activeCount = self.focusedTasks.count + completedCount
        guard activeCount > 0 else { return 0 }
        return min(Double(completedCount) / Double(activeCount), 1)
    }
}
