import SwiftUI

struct ShipBarStateBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(self.title, systemImage: self.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(self.tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(self.tint.opacity(0.12))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(self.tint.opacity(0.22), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

extension ShipBarStateBadge {
    init(runStatus: AgentRunStatus) {
        self.init(
            title: runStatus.displayLabel,
            systemImage: runStatus.shipBarSystemImage,
            tint: runStatus.shipBarTint)
    }
}

private extension AgentRunStatus {
    var shipBarSystemImage: String {
        switch self {
        case .prepared: "doc.badge.gearshape"
        case .handedOff: "paperplane.fill"
        case .running: "bolt.fill"
        case .needsReview: "eye.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .canceled: "xmark.circle"
        }
    }

    var shipBarTint: Color {
        switch self {
        case .prepared: ShipBarStyle.selectionForeground
        case .handedOff, .running: ShipBarStyle.runPurple
        case .needsReview: ShipBarStyle.reviewAmber
        case .completed: ShipBarStyle.successGreen
        case .failed: .red
        case .canceled: .secondary
        }
    }
}
