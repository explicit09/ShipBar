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
                        .lineLimit(self.isFlightPlan ? 1 : 2)
                        .truncationMode(.tail)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help(self.task.title)

            if case .waiting(let status) = self.mode {
                ShipBarStateBadge(runStatus: status)
                    .layoutPriority(2)
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
        .frame(maxWidth: .infinity)
        .frame(height: self.isFlightPlan ? 48 : nil)
        .background {
            RoundedRectangle(cornerRadius: ShipBarStyle.rowRadius, style: .continuous)
                .fill(self.backgroundFill.opacity(self.backgroundFillOpacity))
        }
        .shipBarOutline(
            radius: ShipBarStyle.rowRadius,
            color: self.borderColor,
            increasedColor: self.increasedBorderColor)
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
                .fill(ShipBarStyle.selectionForeground)
                .frame(width: 4, height: 34)
        case .next:
            Circle()
                .fill(ShipBarStyle.selectionForeground.opacity(0.45))
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
            .foregroundStyle(ShipBarStyle.selectionForeground)
            .frame(width: 23, height: 23)
            .background(Circle().fill(ShipBarStyle.selectionSurface))
    }

    private var isNow: Bool {
        if case .now = self.mode { return true }
        return false
    }

    private var isFlightPlan: Bool {
        if case .flightPlan = self.mode { return true }
        return false
    }

    private var backgroundFill: Color {
        switch self.mode {
        case .now: ShipBarStyle.selectionSurface
        case .waiting: ShipBarStyle.reviewAmber.opacity(0.055)
        case .flightPlan, .next: ShipBarStyle.raisedSurface
        }
    }

    private var borderColor: Color {
        switch self.mode {
        case .now: Color.clear
        case .waiting: ShipBarStyle.reviewAmber.opacity(0.18)
        case .flightPlan, .next: ShipBarStyle.subtleStroke
        }
    }

    private var increasedBorderColor: Color {
        switch self.mode {
        case .now: Color.clear
        case .waiting: ShipBarStyle.reviewAmber.opacity(0.64)
        case .flightPlan, .next: ShipBarStyle.increasedContrastStroke
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
