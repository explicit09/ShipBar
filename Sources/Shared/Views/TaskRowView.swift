import SwiftUI

struct TaskRowView: View {
    let task: ShipTask
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                self.toggleDone(self.task)
            } label: {
                Image(systemName: self.task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(self.task.status == .done ? ShipBarStyle.promptGreen : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Button {
                self.selectTask(self.task)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(self.task.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(priorityColor)
                                .frame(width: 6, height: 6)
                            Text(self.task.priority.label)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text(self.task.isInbox ? "Inbox" : (self.task.project?.name ?? "No Project"))
                        Text("·")
                        Text(self.task.type.label)
                        if !self.task.sourceApp.isEmpty {
                            Text("·")
                            Label(self.task.sourceApp, systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        if self.task.hasPrompt {
                            Text("·")
                            Label("Prompt", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(ShipBarStyle.promptGreen)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 0)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ShipBarStyle.separator)
                .frame(height: 1)
        }
    }

    private var priorityColor: Color {
        ShipBarStyle.priorityColor(self.task.priority)
    }
}
