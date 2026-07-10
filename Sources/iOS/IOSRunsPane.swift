#if os(iOS)
import SwiftUI

struct IOSRunsPane: View {
    let runs: [AgentRun]
    let selectRun: (AgentRun) -> Void

    var body: some View {
        let queues = AgentRunQueries.queues(from: self.runs)
        Group {
            if self.runs.isEmpty {
                ContentUnavailableView(
                    "No agent runs",
                    systemImage: "paperplane",
                    description: Text("Prepare a task for an agent to start tracking its handoff."))
            } else {
                List {
                    self.section("Needs Review", runs: queues.needsReview, tint: ShipBarStyle.reviewAmber)
                    self.section("Active", runs: queues.active, tint: ShipBarStyle.runPurple)
                    self.section("Recent", runs: queues.recent, tint: ShipBarStyle.successGreen)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, runs: [AgentRun], tint: Color) -> some View {
        if !runs.isEmpty {
            Section(title) {
                ForEach(runs) { run in
                    Button { self.selectRun(run) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(self.tint(for: run, sectionTint: tint)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.taskTitleSnapshot)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 5) {
                                    Text(run.projectNameSnapshot ?? "Inbox")
                                    Text("·")
                                    Text(self.statusLabel(run.status))
                                    Text("·")
                                    Text(run.target?.label ?? "Unknown agent")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if run.status == .prepared {
                                Text("Ready on Mac")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ShipBarStyle.runPurple)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(run.taskTitleSnapshot), \(self.statusLabel(run.status)), \(run.target?.label ?? "unknown agent")")
                    .accessibilityHint("Opens run review")
                }
            }
        }
    }

    private func statusLabel(_ status: AgentRunStatus) -> String {
        switch status {
        case .handedOff: "Handed off"
        case .needsReview: "Needs review"
        case .prepared: "Ready to hand off on Mac"
        default: status.rawValue.capitalized
        }
    }

    private func tint(for run: AgentRun, sectionTint: Color) -> Color {
        run.status == .failed ? .red : sectionTint
    }
}
#endif
