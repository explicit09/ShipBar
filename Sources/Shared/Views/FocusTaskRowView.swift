import SwiftUI

enum FocusTaskRowMode {
    case flightPlan(position: Int)
    case now
    case next
    case waiting(AgentRunStatus)
}

struct FocusTaskRowView: View {
    let task: ShipTask
    let mode: FocusTaskRowMode
    var backgroundFillOpacity = 1.0
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void
    var removeFocus: ((ShipTask) -> Void)?
    var moveFocus: ((ShipTask, Int) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            self.leadingMark

            Button {
                self.selectTask(self.task)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.task.title)
                        .font(.system(size: self.isNow ? 14 : 13, weight: self.isNow ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(self.task.project?.name ?? "Inbox")
                        if let dueLabel {
                            Text("·")
                            Text(dueLabel)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if case .waiting(let status) = self.mode {
                ShipBarStateBadge(runStatus: status)
            }

            if let removeFocus {
                Button {
                    removeFocus(self.task)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Remove from today's focus")
            } else {
                Button {
                    self.toggleDone(self.task)
                } label: {
                    Image(systemName: self.task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(self.task.status == .done ? ShipBarStyle.successGreen : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(self.task.status == .done ? "Reopen task" : "Mark done")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, self.isNow ? 10 : 8)
        .background {
            RoundedRectangle(cornerRadius: self.isNow ? 11 : 9, style: .continuous)
                .fill(self.backgroundFill.opacity(self.backgroundFillOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: self.isNow ? 11 : 9, style: .continuous)
                .stroke(self.borderColor, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityLabel)
    }

    @ViewBuilder
    private var leadingMark: some View {
        switch self.mode {
        case .flightPlan(let position):
            if let moveFocus {
                Menu {
                    Button("Move up", systemImage: "arrow.up") {
                        moveFocus(self.task, position - 1)
                    }
                    .disabled(position == 1)
                    Button("Move down", systemImage: "arrow.down") {
                        moveFocus(self.task, position + 1)
                    }
                } label: {
                    self.positionBadge(position)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Reorder today's focus")
                .accessibilityLabel("Focus position \(position). Reorder \(self.task.title)")
            } else {
                self.positionBadge(position)
            }
        case .now:
            Capsule()
                .fill(ShipBarStyle.shipBlue)
                .frame(width: 4, height: 34)
                .shadow(color: ShipBarStyle.shipBlue.opacity(0.35), radius: 5)
        case .next:
            Circle()
                .fill(ShipBarStyle.shipBlue.opacity(0.45))
                .frame(width: 7, height: 7)
                .frame(width: 23)
        case .waiting:
            Image(systemName: "hourglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShipBarStyle.reviewAmber)
                .frame(width: 23)
        }
    }

    private func positionBadge(_ position: Int) -> some View {
        Text("\(position)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(ShipBarStyle.shipBlue)
            .frame(width: 23, height: 23)
            .background(Circle().fill(ShipBarStyle.shipBlue.opacity(0.13)))
    }

    private var isNow: Bool {
        if case .now = self.mode { return true }
        return false
    }

    private var backgroundFill: Color {
        switch self.mode {
        case .now: ShipBarStyle.shipBlue.opacity(0.10)
        case .waiting: ShipBarStyle.reviewAmber.opacity(0.055)
        case .flightPlan, .next: ShipBarStyle.raisedSurface
        }
    }

    private var borderColor: Color {
        switch self.mode {
        case .now: ShipBarStyle.shipBlue.opacity(0.30)
        case .waiting: ShipBarStyle.reviewAmber.opacity(0.18)
        case .flightPlan, .next: ShipBarStyle.subtleStroke
        }
    }

    private var dueLabel: String? {
        guard let dueDate = self.task.dueDate else { return nil }
        if Calendar.current.isDateInToday(dueDate) { return "Today" }
        if dueDate < Calendar.current.startOfDay(for: .now) { return "Overdue" }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var accessibilityLabel: String {
        let state: String = switch self.mode {
        case .flightPlan(let position): "Focus position \(position)"
        case .now: "Working now"
        case .next: "Up next"
        case .waiting(let status): "Waiting, \(status.rawValue)"
        }
        return "\(state), \(self.task.title), \(self.task.project?.name ?? "Inbox")"
    }
}
