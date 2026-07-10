import SwiftUI

struct AgentRunsView: View {
    let runs: [AgentRun]
    let selectRun: (AgentRun) -> Void

    private var queues: AgentRunQueues {
        AgentRunQueries.queues(from: self.runs)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                ShipBarPageHeader(title: "Agent runs", purpose: "Delegate the work. Keep the decision.")

                if self.runs.isEmpty {
                    self.emptyState
                } else {
                    self.runSection(
                        "Needs review",
                        detail: "Your decision is required",
                        runs: self.queues.needsReview,
                        tint: ShipBarStyle.reviewAmber)
                    self.runSection(
                        "Active",
                        detail: "Prepared and in progress",
                        runs: self.queues.active,
                        tint: ShipBarStyle.runPurple)
                    self.runSection(
                        "Recent",
                        detail: "Completed run history",
                        runs: self.queues.recent,
                        tint: ShipBarStyle.successGreen)
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func runSection(_ title: String, detail: String, runs: [AgentRun], tint: Color) -> some View {
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        Text(title).font(.system(size: 13, weight: .bold))
                        Text("\(runs.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                ForEach(runs) { run in
                    AgentRunRow(run: run, selectRun: self.selectRun)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "paperplane.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ShipBarStyle.runPurple)
            Text("No agent runs yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Hand off a prepared task. ShipBar will keep the prompt, state, and review decision together.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct AgentRunRow: View {
    let run: AgentRun
    let selectRun: (AgentRun) -> Void

    var body: some View {
        Button {
            self.selectRun(self.run)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: self.run.target?.systemImage ?? "paperplane")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.tint)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(self.tint.opacity(0.11)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.run.taskTitleSnapshot)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(self.run.projectNameSnapshot ?? "No project")
                        Text("·")
                        Text(self.run.target?.label ?? "Unknown agent")
                        Text("·")
                        Text(self.relativeDate)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                ShipBarStateBadge(runStatus: self.run.status)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ShipBarStyle.raisedSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(self.run.status == .failed ? Color.red.opacity(0.3) : ShipBarStyle.subtleStroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(self.run.taskTitleSnapshot), \(self.run.status.rawValue), \(self.run.target?.label ?? "unknown agent")")
    }

    private var relativeDate: String {
        self.run.updatedAt.formatted(.relative(presentation: .named))
    }

    private var tint: Color {
        self.run.status == .failed ? .red : ShipBarStyle.runPurple
    }
}
