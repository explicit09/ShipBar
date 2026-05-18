#if os(iOS)
import SwiftUI

struct IOSProjectListPane: View {
    let projects: [Project]
    let openCount: (Project) -> Int
    let select: (Project) -> Void

    var body: some View {
        if self.projects.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
                Text("No projects yet")
                    .font(.system(size: 17, weight: .semibold))
                Text("Create one to start grouping work.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(self.projects) { project in
                    Button {
                        self.select(project)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(self.tint(for: project).opacity(0.16))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(self.tint(for: project))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                Text(self.subtitle(for: project))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func subtitle(for project: Project) -> String {
        let count = self.openCount(project)
        switch count {
        case 0: return "No open tasks"
        case 1: return "1 open task"
        default: return "\(count) open tasks"
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
#endif
