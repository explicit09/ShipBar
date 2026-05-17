import SwiftUI

struct TaskListView: View {
    let title: String
    let tasks: [ShipTask]
    let selectTask: (ShipTask) -> Void
    let toggleDone: (ShipTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer()
                    Text("\(self.tasks.count) open")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Text("Updated just now")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(ShipBarStyle.separator)
                .frame(height: 1)

            if self.tasks.isEmpty {
                VStack(spacing: 10) {
                    Text("No open tasks")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Capture the next thing worth shipping.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ShipBarProgressBar(progress: self.queuePressure, tint: self.queueTint)
                    HStack(alignment: .firstTextBaseline) {
                        Text(self.queueSummary)
                        Spacer()
                        if self.promptReadyCount > 0 {
                            Label("\(self.promptReadyCount) prompt-ready", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(ShipBarStyle.promptGreen)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(self.tasks) { task in
                            TaskRowView(task: task, selectTask: self.selectTask, toggleDone: self.toggleDone)
                        }
                    }
                }
            }
        }
    }

    private var highPriorityCount: Int {
        self.tasks.filter { $0.priority == .high }.count
    }

    private var promptReadyCount: Int {
        self.tasks.filter(\.hasPrompt).count
    }

    private var queuePressure: Double {
        min(Double(self.tasks.count) / 8, 1)
    }

    private var queueTint: Color {
        self.highPriorityCount > 0 ? ShipBarStyle.priorityColor(.high) : ShipBarStyle.accent
    }

    private var queueSummary: String {
        if self.highPriorityCount > 0 {
            return "\(self.highPriorityCount) high priority"
        }
        return self.tasks.count == 1 ? "1 item in queue" : "\(self.tasks.count) items in queue"
    }
}
